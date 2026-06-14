import Foundation

/// Runs a Claude Code agent as a `claude` subprocess and captures its session id,
/// so a later call can resume the SAME session (project context stays loaded —
/// no cold re-read). Synchronous/blocking; used from the `cam-agents` MCP server.
enum AgentRunner {
    struct Result {
        var sessionId: String?
        var text: String
        var isError: Bool
    }

    enum RunError: LocalizedError {
        case noClaudeCLI
        case spawnFailed(String)
        var errorDescription: String? {
            switch self {
            case .noClaudeCLI: return "claude CLI not found (~/.local/bin, /opt/homebrew/bin, /usr/local/bin)"
            case .spawnFailed(let m): return "spawn failed: \(m)"
            }
        }
    }

    static func locateCLI() -> URL? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Run `agent` with `task`. If `resumeSession` is set, continues that session
    /// (`claude --resume`) — the agent keeps its loaded context.
    static func run(agent: String, task: String, resumeSession: String?, cwd: URL) throws -> Result {
        guard let cli = locateCLI() else { throw RunError.noClaudeCLI }

        var args = ["--agent", agent, "--print", "--output-format", "json"]
        if let resume = resumeSession {
            args.append(contentsOf: ["--resume", resume])
        }
        args.append(task)

        let process = Process()
        process.executableURL = cli
        process.arguments = args
        process.currentDirectoryURL = cwd

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw RunError.spawnFailed(error.localizedDescription)
        }

        // Read fully (output is one JSON object with --output-format json).
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if let obj = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] {
            let session = obj["session_id"] as? String
            let result = (obj["result"] as? String)
                ?? (obj["error"] as? String)
                ?? ""
            let isError = (obj["is_error"] as? Bool) ?? (process.terminationStatus != 0)
            return Result(sessionId: session, text: result, isError: isError)
        }

        // Fallback: couldn't parse JSON — surface raw output / stderr.
        let raw = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return Result(sessionId: nil,
                      text: raw.isEmpty ? err : raw,
                      isError: process.terminationStatus != 0)
    }

    // MARK: - Background

    private static func buildArgs(agent: String, task: String, resumeSession: String?) -> [String] {
        var args = ["--agent", agent, "--print", "--output-format", "json"]
        if let resume = resumeSession { args.append(contentsOf: ["--resume", resume]) }
        args.append(task)
        return args
    }

    /// Launch the agent detached, redirecting output to `logURL`. Returns the running
    /// process (caller persists `processIdentifier`). The child survives the caller —
    /// stop it later via `stop(pid:)`, parse its result via `parseLog`.
    @discardableResult
    static func startBackground(agent: String, task: String, resumeSession: String?,
                                cwd: URL, logURL: URL) throws -> Process {
        guard let cli = locateCLI() else { throw RunError.noClaudeCLI }
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            throw RunError.spawnFailed("cannot open log \(logURL.path)")
        }
        let process = Process()
        process.executableURL = cli
        process.arguments = buildArgs(agent: agent, task: task, resumeSession: resumeSession)
        process.currentDirectoryURL = cwd
        process.standardOutput = handle
        process.standardError = handle
        do { try process.run() } catch { throw RunError.spawnFailed(error.localizedDescription) }
        return process
    }

    /// Parse a finished background run's log into a Result (session id + final text).
    static func parseLog(_ logURL: URL) -> Result? {
        guard let data = try? Data(contentsOf: logURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Result(sessionId: obj["session_id"] as? String,
                      text: (obj["result"] as? String) ?? (obj["error"] as? String) ?? "",
                      isError: (obj["is_error"] as? Bool) ?? false)
    }

    /// Is a process still alive? (`kill(pid, 0)`).
    static func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    /// Stop a background run (SIGTERM, then SIGKILL fallback handled by OS later).
    @discardableResult
    static func stop(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, SIGTERM) == 0
    }
}
