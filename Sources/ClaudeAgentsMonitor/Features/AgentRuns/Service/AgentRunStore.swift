import Foundation

/// Persisted record of an agent run, so a later turn can resume the SAME claude
/// session (`claude --resume <sessionId>`) instead of cold-spawning the agent
/// (which would re-read the whole project). Keyed by a short `runId`.
struct AgentRun: Codable, Identifiable, Equatable {
    var id: String          // runId
    var agent: String
    var sessionId: String?  // claude session to resume
    var lastTask: String
    var status: String      // running | done | failed | stopped
    var updatedAtMillis: Int64
    var pid: Int32?         // process id while running (for background stop)
    var background: Bool = false

    var updatedAt: Date { Date(timeIntervalSince1970: Double(updatedAtMillis) / 1000) }
    var isRunning: Bool { status == "running" }
}

/// JSON-file store of agent runs (one file per project), shared between the
/// `cam-agents` MCP server and the CAM UI.
final class AgentRunStore {
    private let url: URL
    private let lock = NSLock()

    /// Directory holding per-run output logs.
    let runsDir: URL

    init(path: URL) {
        url = path
        runsDir = path.deletingLastPathComponent().appendingPathComponent("runs")
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
    }

    func logURL(_ runId: String) -> URL { runsDir.appendingPathComponent("\(runId).out") }

    convenience init(paths: AgentPaths) {
        self.init(path: paths.memoryDir.appendingPathComponent("agent-runs.json"))
    }

    static func newRunID() -> String {
        "run_" + String(UInt64.random(in: UInt64.min ... UInt64.max), radix: 36)
    }

    func all() -> [AgentRun] {
        lock.lock(); defer { lock.unlock() }
        return load().values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
    }

    func get(_ id: String) -> AgentRun? {
        lock.lock(); defer { lock.unlock() }
        return load()[id]
    }

    /// Most recent run for an agent (any status) — used to continue "the be-developer".
    func latest(forAgent agent: String) -> AgentRun? {
        all().first { $0.agent == agent }
    }

    func upsert(_ run: AgentRun) {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        var r = run
        r.updatedAtMillis = nowMillis()
        dict[run.id] = r
        save(dict)
    }

    func remove(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        dict.removeValue(forKey: id)
        save(dict)
    }

    /// Sync `running` runs against reality: if a background process is gone, parse its
    /// log for the final session/status. Returns the up-to-date list.
    @discardableResult
    func reconcileRunning() -> [AgentRun] {
        for run in all() where run.isRunning && run.background {
            guard let pid = run.pid else { continue }
            if !AgentRunner.isAlive(pid: pid) {
                var r = run
                if let res = AgentRunner.parseLog(logURL(run.id)) {
                    r.sessionId = res.sessionId ?? run.sessionId
                    r.status = res.isError ? "failed" : "done"
                } else {
                    r.status = "failed"
                }
                r.pid = nil
                upsert(r)
            }
        }
        return all()
    }

    /// Stop a running background run (kills the process), mark it stopped.
    func stop(_ id: String) {
        guard let run = get(id), let pid = run.pid else { return }
        _ = AgentRunner.stop(pid: pid)
        var r = run; r.status = "stopped"; r.pid = nil
        upsert(r)
    }

    func tailLog(_ id: String, maxBytes: Int = 4000) -> String {
        guard let data = try? Data(contentsOf: logURL(id)) else { return "" }
        let slice = data.suffix(maxBytes)
        let raw = String(data: slice, encoding: .utf8) ?? ""
        // Background logs are JSON; show the result text if parseable, else raw tail.
        if let res = AgentRunner.parseLog(logURL(id)), !res.text.isEmpty { return res.text }
        return raw
    }

    // MARK: - IO

    private func load() -> [String: AgentRun] {
        guard let data = try? Data(contentsOf: url),
              let runs = try? JSONDecoder().decode([String: AgentRun].self, from: data)
        else { return [:] }
        return runs
    }

    private func save(_ dict: [String: AgentRun]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
