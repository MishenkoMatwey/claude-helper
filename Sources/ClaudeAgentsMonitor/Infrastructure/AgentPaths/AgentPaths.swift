import Foundation

/// Resolves where agents/workflows/schedules/memory live for the active project.
/// Defaults to the global `~/.claude/agents/` namespace.
struct AgentPaths {
    let projectName: String
    let projectId: String       // stable id used for Keychain prefixes
    let projectRoot: URL        // path to the project (`~` for global)
    let agentsRoot: URL         // `<projectRoot>/.claude/agents`

    var workflowsDir: URL { agentsRoot.appendingPathComponent("workflows") }
    var schedulesDir: URL { agentsRoot.appendingPathComponent("schedules") }
    var memoryDir: URL { agentsRoot.appendingPathComponent("memory") }

    static let global: AgentPaths = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AgentPaths(
            projectName: "User (global)",
            projectId: "user",
            projectRoot: home,
            agentsRoot: home.appendingPathComponent(".claude/agents")
        )
    }()

    static func project(name: String, root: URL) -> AgentPaths {
        AgentPaths(
            projectName: name,
            projectId: shortHash(of: root.path),
            projectRoot: root,
            agentsRoot: root.appendingPathComponent(".claude/agents")
        )
    }

    private static func shortHash(of s: String) -> String {
        var hash: UInt64 = 5381
        for byte in s.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 36).prefix(10).description
    }

    /// Mutable singleton — set by AppState when current project changes.
    nonisolated(unsafe) static var current: AgentPaths = .global
}
