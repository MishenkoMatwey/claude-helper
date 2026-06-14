import Foundation

protocol PermissionsService {
    func load(for agent: Agent, in project: ClaudeProject) -> [PermissionEntry]
    func promote(pattern: String, into agent: Agent) throws
    func removeFromAgent(pattern: String, agent: Agent) throws
    func addCustom(pattern: String, agent: Agent) throws
    func removeFromSettings(pattern: String, scope: PermissionEntry.Scope, in project: ClaudeProject) throws
    func addToSettings(pattern: String, scope: PermissionEntry.Scope, in project: ClaudeProject) throws
    func move(pattern: String, fromScope scope: PermissionEntry.Scope,
              into agent: Agent, in project: ClaudeProject) throws
    func generalize(_ pattern: String) -> String
}

struct PermissionsServiceLive: PermissionsService {
    func load(for agent: Agent, in project: ClaudeProject) -> [PermissionEntry] {
        EffectivePermissions.load(for: agent, in: project)
    }
    func promote(pattern: String, into agent: Agent) throws {
        try EffectivePermissions.promote(pattern: pattern, into: agent)
    }
    func removeFromAgent(pattern: String, agent: Agent) throws {
        try EffectivePermissions.removeFromAgent(pattern: pattern, agent: agent)
    }
    func addCustom(pattern: String, agent: Agent) throws {
        try EffectivePermissions.addCustomToAgent(pattern: pattern, agent: agent)
    }
    func removeFromSettings(pattern: String, scope: PermissionEntry.Scope, in project: ClaudeProject) throws {
        try EffectivePermissions.removeFromSettings(pattern: pattern, scope: scope, in: project)
    }
    func addToSettings(pattern: String, scope: PermissionEntry.Scope, in project: ClaudeProject) throws {
        try EffectivePermissions.addToSettings(pattern: pattern, scope: scope, in: project)
    }
    func move(pattern: String, fromScope scope: PermissionEntry.Scope,
              into agent: Agent, in project: ClaudeProject) throws {
        try EffectivePermissions.move(pattern: pattern, fromScope: scope, into: agent, in: project)
    }
    func generalize(_ pattern: String) -> String { EffectivePermissions.generalize(pattern) }
}
