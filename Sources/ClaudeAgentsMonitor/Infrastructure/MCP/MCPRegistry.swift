import Foundation

struct MCPServer: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let scope: String   // e.g. "user (global)" / "<project path>"
    let command: String?
}

enum MCPRegistry {
    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
    }

    /// Returns MCP servers configured at any project scope, with "current project" first.
    static func loadAvailable(currentProjectPath: String?) -> [MCPServer] {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var allServers: [String: MCPServer] = [:]

        if let projects = json["projects"] as? [String: Any] {
            for (path, raw) in projects {
                guard let cfg = raw as? [String: Any],
                      let servers = cfg["mcpServers"] as? [String: Any]
                else { continue }
                for (name, serverCfg) in servers {
                    let cmd = (serverCfg as? [String: Any])?["command"] as? String
                    let scope = (path == FileManager.default.homeDirectoryForCurrentUser.path)
                        ? "user (global)"
                        : path
                    if allServers[name] == nil {
                        allServers[name] = MCPServer(name: name, scope: scope, command: cmd)
                    }
                }
            }
        }

        // Top-level mcpServers (alternative location)
        if let top = json["mcpServers"] as? [String: Any] {
            for (name, serverCfg) in top {
                let cmd = (serverCfg as? [String: Any])?["command"] as? String
                if allServers[name] == nil {
                    allServers[name] = MCPServer(name: name, scope: "user (global)", command: cmd)
                }
            }
        }

        // Hide MCP servers we don't actually integrate with — keeps the agent form
        // focused on servers that meaningfully matter for subagents.
        let hidden: Set<String> = ["ruflo"]
        return allServers.values
            .filter { !hidden.contains($0.name) }
            .sorted { $0.name < $1.name }
    }
}
