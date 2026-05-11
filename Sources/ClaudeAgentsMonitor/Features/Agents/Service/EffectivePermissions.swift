import Foundation

struct PermissionEntry: Identifiable, Hashable {
    var id: String { "\(scope.rawValue):\(pattern)" }
    let pattern: String
    let scope: Scope

    enum Scope: String, CaseIterable {
        case agent      // declared in agent .md frontmatter
        case projectAllow      // <project>/.claude/settings.local.json permissions.allow
        case projectDeny       // permissions.deny
        case userAllow         // ~/.claude/settings.json permissions.allow
        case userDeny          // ~/.claude/settings.json permissions.deny
    }
}

enum EffectivePermissions {
    static func load(for agent: Agent, in project: ClaudeProject) -> [PermissionEntry] {
        var entries: [PermissionEntry] = []
        for tool in agent.tools {
            entries.append(PermissionEntry(pattern: tool, scope: .agent))
        }
        let projectSettings = project.url
            .appendingPathComponent(".claude/settings.local.json")
        let userSettings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        for (path, allowScope, denyScope) in [
            (projectSettings, PermissionEntry.Scope.projectAllow, PermissionEntry.Scope.projectDeny),
            (userSettings, PermissionEntry.Scope.userAllow, PermissionEntry.Scope.userDeny)
        ] {
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let perms = json["permissions"] as? [String: Any]
            else { continue }
            if let allow = perms["allow"] as? [String] {
                for a in allow {
                    entries.append(PermissionEntry(pattern: a, scope: allowScope))
                }
            }
            if let deny = perms["deny"] as? [String] {
                for d in deny {
                    entries.append(PermissionEntry(pattern: d, scope: denyScope))
                }
            }
        }
        return entries
    }

    /// Promote a permission from inherited (project/user) into the agent's own tools list.
    static func promote(pattern: String, into agent: Agent) throws {
        var newTools = agent.tools
        if !newTools.contains(pattern) {
            newTools.append(pattern)
        }
        _ = try AgentWriter.save(
            name: agent.name,
            description: agent.description,
            model: agent.model ?? "default",
            tools: newTools,
            systemPrompt: agent.promptWithoutInjectedBlocks,
            skills: [],
            overwrite: true
        )
    }
}
