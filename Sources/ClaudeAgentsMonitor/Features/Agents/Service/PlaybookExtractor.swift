import Foundation

struct SessionRef: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let project: String
    let modifiedAt: Date
    let messageCount: Int

    var displayName: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return "\(project) — \(f.string(from: modifiedAt))"
    }
}

enum ExtractionError: LocalizedError {
    case noClaudeCLI
    case noSessions
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noClaudeCLI: return "Claude CLI not found in PATH. Install via `npm i -g @anthropic-ai/claude-code` or check ~/.local/bin"
        case .noSessions: return "No Claude Code sessions found in ~/.claude/projects/"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        }
    }
}

enum PlaybookExtractor {
    static func recentSessions(limit: Int = 15) -> [SessionRef] {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projects,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var refs: [SessionRef] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = attrs.contentModificationDate
            else { continue }
            let project = url.deletingLastPathComponent().lastPathComponent
                .replacingOccurrences(of: "-", with: "/")
            let count = quickCount(url: url)
            refs.append(SessionRef(url: url, project: project, modifiedAt: modified, messageCount: count))
        }
        return refs.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit).map { $0 }
    }

    private static func quickCount(url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        return data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// Reads the JSONL session, extracts user/assistant text turns and feeds them to `claude -p` for distillation.
    static func extract(
        from session: SessionRef,
        agentName: String,
        progress: @escaping (String) -> Void
    ) async throws -> String {
        progress("Reading session…")
        let transcript = try buildTranscript(from: session.url, maxChars: 60_000)

        progress("Locating claude CLI…")
        guard let cli = locateClaudeCLI() else { throw ExtractionError.noClaudeCLI }

        let prompt = """
        Ты — экстрактор playbook'ов. На входе — транскрипт Claude Code сессии.
        Задача: извлечь воспроизводимый playbook для агента '\(agentName)'.

        Если в сессии есть конкретная многошаговая процедура (API-вызовы, CLI-команды, рабочий процесс
        с внешним инструментом) — оформи её в формате ниже. Если ничего достойного нет — верни ровно
        одну строку: SKIP

        Формат playbook (без markdown-блока, без объяснений вокруг):
        ## <короткое-имя-snake-case>
        **Trigger**: "фраза1", "фраза2"
        **Last verified**: \(today())
        **Tokens cost**: ~<оценка если можешь>

        ### Steps
        1. <команда / API call>
        2. <шаг>

        ### Notes
        - <подводные камни>

        ### Example output
        <фрагмент>

        ===== TRANSCRIPT =====
        \(transcript)
        ===== END =====
        """

        progress("Asking Claude to extract…")
        let result = try await runProcess(
            cli,
            args: ["-p", prompt, "--output-format", "text"],
            timeout: 120
        )
        progress("Done.")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appendPlaybook(_ text: String, to playbooksURL: URL) throws {
        let existing = (try? String(contentsOf: playbooksURL, encoding: .utf8)) ?? ""
        let separator = existing.hasSuffix("\n\n") ? "" : "\n\n"
        let combined = existing + separator + text + "\n"
        try combined.write(to: playbooksURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func locateClaudeCLI() -> URL? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func buildTranscript(from url: URL, maxChars: Int) throws -> String {
        guard let stream = StreamReader(url: url) else {
            throw ExtractionError.extractionFailed("can't open \(url.lastPathComponent)")
        }
        var lines: [String] = []
        var total = 0
        while let raw = stream.nextLine() {
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let role: String
            let text: String
            if let type = obj["type"] as? String, type == "user",
               let msg = obj["message"] as? [String: Any] {
                role = "USER"
                text = stringify(msg["content"]) ?? ""
            } else if let msg = obj["message"] as? [String: Any],
                      let r = msg["role"] as? String, r == "assistant" {
                role = "ASSISTANT"
                text = stringify(msg["content"]) ?? ""
            } else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let line = "[\(role)] \(trimmed)"
            total += line.count + 1
            lines.append(line)
        }
        // Keep tail if exceeds budget
        if total <= maxChars { return lines.joined(separator: "\n") }
        var keep: [String] = []
        var size = 0
        for line in lines.reversed() {
            size += line.count + 1
            if size > maxChars { break }
            keep.insert(line, at: 0)
        }
        return "[…earlier turns truncated…]\n" + keep.joined(separator: "\n")
    }

    private static func stringify(_ content: Any?) -> String? {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            var parts: [String] = []
            for item in arr {
                if let t = item["type"] as? String {
                    if t == "text", let txt = item["text"] as? String { parts.append(txt) }
                    else if t == "tool_use", let name = item["name"] as? String {
                        parts.append("[tool_use: \(name)]")
                    } else if t == "tool_result" {
                        parts.append("[tool_result]")
                    }
                }
            }
            return parts.joined(separator: "\n")
        }
        return nil
    }

    private static func runProcess(
        _ executable: URL,
        args: [String],
        timeout: TimeInterval
    ) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ExtractionError.extractionFailed(error.localizedDescription))
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                    continuation.resume(throwing: ExtractionError.extractionFailed("timeout after \(Int(timeout))s"))
                }
            }
            timer.resume()
            DispatchQueue.global().async {
                process.waitUntilExit()
                timer.cancel()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: ExtractionError.extractionFailed("exit \(process.terminationStatus): \(err.isEmpty ? out : err)"))
                } else {
                    continuation.resume(returning: out)
                }
            }
        }
    }
}
