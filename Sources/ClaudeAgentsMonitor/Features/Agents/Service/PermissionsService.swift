import Foundation

protocol PermissionsService {
    func load(for agent: Agent, in project: ClaudeProject) -> [PermissionEntry]
    func promote(pattern: String, into agent: Agent) throws
}

struct PermissionsServiceLive: PermissionsService {
    func load(for agent: Agent, in project: ClaudeProject) -> [PermissionEntry] {
        EffectivePermissions.load(for: agent, in: project)
    }
    func promote(pattern: String, into agent: Agent) throws {
        try EffectivePermissions.promote(pattern: pattern, into: agent)
    }
}
