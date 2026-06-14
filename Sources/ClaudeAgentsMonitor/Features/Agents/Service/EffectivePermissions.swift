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
        try setAgentTools(agent: agent) { $0.contains(pattern) ? $0 : $0 + [pattern] }
    }

    /// Move = promote into agent + remove from the source settings file.
    /// Use when the user clicks "Move into agent" in the chip menu.
    static func move(pattern: String, fromScope scope: PermissionEntry.Scope,
                     into agent: Agent, in project: ClaudeProject) throws {
        try promote(pattern: pattern, into: agent)
        try removeFromSettings(pattern: pattern, scope: scope, in: project)
    }

    /// Heuristic that strips JWTs, UUIDs, long opaque tokens and date stamps —
    /// turning a one-shot approval like
    ///   `Bash(curl ... Bearer eyJ...long... /reports?id=ab12...)`
    /// into a stable wildcard that survives token rotation:
    ///   `Bash(curl *Bearer* /reports*)`
    static func generalize(_ pattern: String) -> String {
        var s = pattern
        // JWT (header.payload.signature, base64url-ish)
        s = regexReplace(s, #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#, "*")
        // UUID
        s = regexReplace(s, #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#, "*")
        // Atlassian / Figma / generic opaque ≥ 40 chars
        s = regexReplace(s, #"[A-Za-z0-9_\-]{40,}"#, "*")
        // Dates YYYY-MM-DD and YYYYMMDD-ish
        s = regexReplace(s, #"\d{4}-\d{2}-\d{2}"#, "*")
        s = regexReplace(s, #"\b\d{8}\b"#, "*")
        // Collapse runs of wildcards.
        while s.contains("**") { s = s.replacingOccurrences(of: "**", with: "*") }
        return s
    }

    private static func regexReplace(_ src: String, _ pattern: String, _ replacement: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return src }
        let range = NSRange(src.startIndex..., in: src)
        return re.stringByReplacingMatches(in: src, range: range, withTemplate: replacement)
    }

    static func removeFromAgent(pattern: String, agent: Agent) throws {
        try setAgentTools(agent: agent) { $0.filter { $0 != pattern } }
    }

    static func addCustomToAgent(pattern: String, agent: Agent) throws {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try promote(pattern: trimmed, into: agent)
    }

    /// Remove a pattern from `permissions.allow` or `permissions.deny` in the given scope's settings file.
    static func removeFromSettings(pattern: String, scope: PermissionEntry.Scope, in project: ClaudeProject) throws {
        guard let url = settingsURL(for: scope, project: project) else { return }
        let key = (scope == .projectDeny || scope == .userDeny) ? "deny" : "allow"
        try mutateSettings(at: url) { settings in
            var perms = (settings["permissions"] as? [String: Any]) ?? [:]
            if var list = perms[key] as? [String] {
                list.removeAll { $0 == pattern }
                perms[key] = list
            }
            settings["permissions"] = perms
        }
    }

    /// Re-add a pattern into the given scope's settings file.
    static func addToSettings(pattern: String, scope: PermissionEntry.Scope, in project: ClaudeProject) throws {
        guard let url = settingsURL(for: scope, project: project) else { return }
        let key = (scope == .projectDeny || scope == .userDeny) ? "deny" : "allow"
        try mutateSettings(at: url) { settings in
            var perms = (settings["permissions"] as? [String: Any]) ?? [:]
            var list = (perms[key] as? [String]) ?? []
            if !list.contains(pattern) { list.append(pattern) }
            perms[key] = list
            settings["permissions"] = perms
        }
    }

    private static func setAgentTools(agent: Agent, _ transform: ([String]) -> [String]) throws {
        let newTools = transform(agent.tools)
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

    private static func settingsURL(for scope: PermissionEntry.Scope, project: ClaudeProject) -> URL? {
        switch scope {
        case .projectAllow, .projectDeny:
            return project.url.appendingPathComponent(".claude/settings.local.json")
        case .userAllow, .userDeny:
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/settings.json")
        case .agent:
            return nil
        }
    }

    private static func mutateSettings(at url: URL, _ transform: (inout [String: Any]) -> Void) throws {
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = dict
        }
        transform(&settings)
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }
}
