import Foundation

enum WorkflowRunnerError: LocalizedError {
    case noClaudeCLI
    case spawnFailed(String)
    case nonZeroExit(Int32, String)

    var errorDescription: String? {
        switch self {
        case .noClaudeCLI: return "claude CLI not found"
        case .spawnFailed(let m): return "spawn failed: \(m)"
        case .nonZeroExit(let code, let msg): return "exit \(code): \(msg)"
        }
    }
}

/// Runs a workflow by invoking the orchestrator agent with the given trigger phrase.
/// Streams stdout line-by-line and emits structured status updates.
@MainActor
final class WorkflowRunner: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    @Published private(set) var sessionId: String?
    @Published private(set) var rateLimitedReset: Date?

    enum Status: Equatable {
        case idle
        case running
        case finished(success: Bool)
        case rateLimited
    }

    private var process: Process?

    var elapsedSeconds: Double {
        guard let started = startedAt else { return 0 }
        let end = finishedAt ?? Date()
        return end.timeIntervalSince(started)
    }

    func run(workflow: Workflow?, agentName: String, trigger: String, autoResume: Bool, fiveHourResetAt: Date?, weeklyResetAt: Date?) {
        guard status != .running else { return }
        lines = []
        status = .running
        startedAt = Date()
        finishedAt = nil
        sessionId = nil
        rateLimitedReset = nil

        Task.detached { [weak self] in
            await self?.execute(
                workflow: workflow,
                agentName: agentName,
                trigger: trigger,
                resumeSession: nil,
                autoResume: autoResume,
                fiveHourResetAt: fiveHourResetAt,
                weeklyResetAt: weeklyResetAt
            )
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
    }

    private func locateClaudeCLI() -> URL? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func execute(
        workflow: Workflow?,
        agentName: String,
        trigger: String,
        resumeSession: String?,
        autoResume: Bool,
        fiveHourResetAt: Date?,
        weeklyResetAt: Date?
    ) async {
        guard let cli = await MainActor.run(body: { locateClaudeCLI() }) else {
            await append("[error] claude CLI not found in ~/.local/bin or /opt/homebrew/bin")
            await markFinished(success: false)
            return
        }

        let process = Process()
        process.executableURL = cli
        var args: [String] = ["--agent", agentName, "--print",
                              "--output-format", "stream-json",
                              "--include-partial-messages",
                              "--verbose"]
        if let resume = resumeSession {
            args.append(contentsOf: ["--resume", resume])
        }
        args.append(trigger)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        await MainActor.run { self.process = process }

        do {
            try process.run()
        } catch {
            await append("[error] spawn failed: \(error.localizedDescription)")
            await markFinished(success: false)
            return
        }

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        let outTask = Task.detached { [weak self] in
            await self?.streamLines(handle: outHandle, errChannel: false)
        }
        let errTask = Task.detached { [weak self] in
            await self?.streamLines(handle: errHandle, errChannel: true)
        }

        process.waitUntilExit()
        _ = await outTask.result
        _ = await errTask.result

        let success = process.terminationStatus == 0
        if !success {
            await append("[exit \(process.terminationStatus)]")
        }

        // Check if we hit a rate limit and should pause for resume.
        let hitRateLimit = await MainActor.run { self.rateLimitedReset != nil }
        if hitRateLimit, let session = await MainActor.run(body: { self.sessionId }) {
            await markFinished(success: false)
            await MainActor.run { self.status = .rateLimited }
            if autoResume {
                let resumeKind: PausedExecution.ResumeKind = (await MainActor.run { rateLimitedReset == fiveHourResetAt }) ? .fiveHour : .weekly
                let resetAt = await MainActor.run { rateLimitedReset }
                let pause = PausedExecution(
                    sessionId: session,
                    agentName: agentName,
                    workflowName: workflow?.name,
                    originalPrompt: trigger,
                    pausedAt: Date(),
                    reason: resumeKind == .fiveHour ? "5-hour rate limit" : "weekly limit",
                    resumeAfter: resetAt,
                    resumeKind: resumeKind,
                    attempts: 1
                )
                PausedExecutionStore.add(pause)
                await append("⏸ Paused — auto-resume registered for next \(resumeKind == .fiveHour ? "5h" : "weekly") reset.")
                await MainActor.run {
                    NotificationService.notifyRateLimitPaused(workflow: workflow?.name, resumeAt: resetAt)
                }
            }
        } else {
            await markFinished(success: success)
        }
        await MainActor.run { self.process = nil }
    }

    private func streamLines(handle: FileHandle, errChannel: Bool) async {
        var buffer = Data()
        let delimiter = Data([0x0A])
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            buffer.append(data)
            while let range = buffer.range(of: delimiter) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    if errChannel {
                        await detectRateLimit(in: line)
                        await append("[stderr] \(line)")
                    } else {
                        await captureSessionId(line)
                        await detectRateLimit(in: line)
                        let pretty = prettifyStreamJSON(line)
                        if !pretty.isEmpty { await append(pretty) }
                    }
                }
            }
        }
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
            await append(errChannel ? "[stderr] \(line)" : prettifyStreamJSON(line))
        }
    }

    private func captureSessionId(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let type = obj["type"] as? String, type == "system",
           let id = obj["session_id"] as? String {
            await MainActor.run { self.sessionId = id }
        }
    }

    private func detectRateLimit(in line: String) async {
        let lower = line.lowercased()
        if lower.contains("rate_limit") || lower.contains("rate limit")
            || lower.contains("\"status\":429") || lower.contains("error 429") {
            // Try to find resets_at hint; otherwise default to 5h.
            await MainActor.run {
                if self.rateLimitedReset == nil {
                    self.rateLimitedReset = Date().addingTimeInterval(5 * 3600)
                }
            }
        }
    }

    private func prettifyStreamJSON(_ line: String) -> String {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return line }
        let type = obj["type"] as? String ?? "?"
        switch type {
        case "system":
            if let subtype = obj["subtype"] as? String {
                if let session = obj["session_id"] as? String {
                    return "▶ system: \(subtype)  session=\(String(session.prefix(8)))"
                }
                return "▶ system: \(subtype)"
            }
            return ""
        case "assistant":
            if let msg = obj["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]] {
                var parts: [String] = []
                for c in content {
                    if let t = c["type"] as? String {
                        if t == "text", let txt = c["text"] as? String, !txt.isEmpty {
                            parts.append(txt)
                        } else if t == "tool_use",
                                  let name = c["name"] as? String {
                            let input = c["input"] as? [String: Any] ?? [:]
                            if name == "Task",
                               let subagent = input["subagent_type"] as? String,
                               let desc = input["description"] as? String {
                                parts.append("→ Task(\(subagent)): \(desc)")
                            } else {
                                parts.append("→ \(name)")
                            }
                        }
                    }
                }
                return parts.joined(separator: "\n")
            }
            return ""
        case "user":
            if let msg = obj["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]] {
                for c in content {
                    if let t = c["type"] as? String, t == "tool_result" {
                        let result = (c["content"] as? String)
                            ?? (c["content"] as? [[String: Any]])?
                                .compactMap { $0["text"] as? String }
                                .joined(separator: "\n")
                            ?? ""
                        let head = result.split(separator: "\n").prefix(3).joined(separator: " ")
                        return "  ✓ \(head.prefix(180))"
                    }
                }
            }
            return ""
        case "result":
            let cost = (obj["total_cost_usd"] as? Double).map { String(format: " $%.4f", $0) } ?? ""
            let durMs = (obj["duration_ms"] as? Int).map { " \($0/1000)s" } ?? ""
            let inT = (obj["usage"] as? [String: Any])?["input_tokens"] as? Int ?? 0
            let outT = (obj["usage"] as? [String: Any])?["output_tokens"] as? Int ?? 0
            return "■ done\(durMs)\(cost)  in:\(inT) out:\(outT)"
        default:
            return ""
        }
    }

    private func append(_ s: String) async {
        await MainActor.run { self.lines.append(s) }
    }

    private func markFinished(success: Bool) async {
        await MainActor.run {
            self.status = .finished(success: success)
            self.finishedAt = Date()
        }
    }
}

// MARK: - Background resumer (called by AppState)

enum ExecutionResumer {
    static func resumeAll(matching kind: PausedExecution.ResumeKind) async {
        let paused = PausedExecutionStore.loadAll().filter { $0.resumeKind == kind }
        guard !paused.isEmpty else { return }
        let cli = locateCLI()
        guard let cli else { return }
        for var p in paused {
            p.attempts += 1
            PausedExecutionStore.update(p)
            let process = Process()
            process.executableURL = cli
            process.arguments = [
                "--resume", p.sessionId,
                "--agent", p.agentName,
                "--print",
                "--output-format", "json",
                "Continue. Лимит сбросился, продолжай задачу с того места где прервался."
            ]
            let outPipe = Pipe(); let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
            } catch {
                NSLog("ClaudeAgentsMonitor: resume failed: %@", "\(error)")
                continue
            }
            DispatchQueue.global().async {
                process.waitUntilExit()
                _ = outPipe.fileHandleForReading.readDataToEndOfFile()
                _ = errPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    PausedExecutionStore.remove(p.id)
                }
                // If failed again — leave in list for next reset; attempts already incremented.
            }
        }
    }

    private static func locateCLI() -> URL? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
