import Foundation

/// Registers the per-agent memory MCP server into the project's `.mcp.json`,
/// so the `claude` CLI launches CAM (`--mcp-serve`) and exposes the memory tools.
///
/// One server per agent (`cam-memory-<agent>`) so each agent's notes are scoped
/// to it by default; the server's tools surface to the agent as
/// `mcp__cam-memory-<agent>__memory_search` etc.
enum MemoryMCPConfig {
    static func serverName(for agent: String) -> String { "cam-memory-\(agent)" }

    /// Path to the running CAM binary — used as the MCP server command.
    static var binaryPath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "ClaudeAgentsMonitor"
    }

    /// Merge (or refresh) the agent's memory server entry in `<projectRoot>/.mcp.json`.
    static func register(agentName: String, paths: AgentPaths) {
        let url = paths.projectRoot.appendingPathComponent(".mcp.json")

        var root = readJSON(url)
        var servers = root["mcpServers"] as? [String: Any] ?? [:]

        servers[serverName(for: agentName)] = [
            "command": binaryPath,
            "args": [
                "--mcp-serve",
                "--db", paths.memoryDBFile.path,
                "--agent", agentName,
            ],
        ]
        root["mcpServers"] = servers
        writeJSON(root, to: url)
    }

    /// Project-wide agent-control server (resumable agent sessions for the orchestrator).
    static let agentsServerName = "cam-agents"

    static func registerAgentControl(paths: AgentPaths) {
        let url = paths.projectRoot.appendingPathComponent(".mcp.json")
        var root = readJSON(url)
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[agentsServerName] = [
            "command": binaryPath,
            "args": ["--agents-serve", "--project", paths.projectRoot.path],
        ]
        root["mcpServers"] = servers
        writeJSON(root, to: url)
    }

    /// Remove the agent's memory server entry (on agent delete).
    static func unregister(agentName: String, paths: AgentPaths) {
        let url = paths.projectRoot.appendingPathComponent(".mcp.json")
        var root = readJSON(url)
        guard var servers = root["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: serverName(for: agentName))
        root["mcpServers"] = servers
        writeJSON(root, to: url)
    }

    // MARK: - JSON helpers (preserve unrelated keys)

    private static func readJSON(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func writeJSON(_ obj: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
