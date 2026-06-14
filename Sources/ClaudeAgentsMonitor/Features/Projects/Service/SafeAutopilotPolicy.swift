import Foundation

/// Project-wide "autopilot" preset: switch the project into Claude Code's
/// `bypassPermissions` mode so agents never ask for approval, but keep a tight
/// DENY list so they still can't mutate external systems (DB, Jira/Confluence,
/// git push, package publish, MCP writes, gh state-changing commands).
///
/// Writes `<project>/.claude/settings.local.json`. Unrelated user rules are
/// preserved — we only add/remove our own keys.
enum SafeAutopilotPolicy {

    /// Claude Code mode that skips ALL permission prompts. Deny still applies.
    static let defaultMode = "bypassPermissions"

    /// Readonly tools are unconditionally allowed — so they keep working even
    /// if someone later flips defaultMode back to "default". Bypass already
    /// covers them; this list is a safety-net + makes intent explicit.
    static let allow: [String] = [
        "Read",
        "Glob",
        "Grep",
        "LS",
        "TodoWrite",
        "WebSearch",
        "WebFetch",
        "NotebookRead",
        "Bash(ls:*)",
        "Bash(cat:*)",
        "Bash(grep:*)",
        "Bash(find:*)",
        "Bash(pwd)",
        "Bash(echo:*)",
        "Bash(git status:*)",
        "Bash(git log:*)",
        "Bash(git diff:*)",
        "Bash(git branch:*)",
        "Bash(git show:*)"
    ]

    /// Patterns that must never run — write/edit/delete in EXTERNAL systems.
    /// Local file edits and any read (DB selects via CLI, WebFetch, jira list)
    /// stay allowed via bypass mode.
    static let deny: [String] = [
        // git push to remote (any form)
        "Bash(git push)",
        "Bash(git push:*)",
        "Bash(git push *)",
        "Bash(git push --force:*)",
        "Bash(git push -f:*)",
        "Bash(git push --force-with-lease:*)",

        // Jira CLI — only write subcommands (list/view/search stay allowed)
        "Bash(jira issue create:*)",
        "Bash(jira issue edit:*)",
        "Bash(jira issue delete:*)",
        "Bash(jira issue move:*)",
        "Bash(jira issue assign:*)",
        "Bash(jira issue link:*)",
        "Bash(jira issue unlink:*)",
        "Bash(jira issue comment add:*)",
        "Bash(jira sprint add:*)",
        "Bash(jira sprint create:*)",
        "Bash(jira epic add:*)",
        "Bash(jira epic create:*)",
        "Bash(acli * create:*)",
        "Bash(acli * edit:*)",
        "Bash(acli * delete:*)",
        "Bash(acli * update:*)",

        // curl / wget to Atlassian / Slack — write methods (POST/PUT/PATCH/DELETE)
        "Bash(curl*-X POST*atlassian*)",
        "Bash(curl*-X PUT*atlassian*)",
        "Bash(curl*-X PATCH*atlassian*)",
        "Bash(curl*-X DELETE*atlassian*)",
        "Bash(curl*--request POST*atlassian*)",
        "Bash(curl*--request PUT*atlassian*)",
        "Bash(curl*--request DELETE*atlassian*)",
        "Bash(curl*-X POST*hooks.slack.com*)",
        "Bash(curl*-X POST*slack.com*)",

        // database write CLIs — SQL is read-or-write so we deny the obvious
        // shorthands; agents can still run psql -c \"SELECT…\" via explicit allow.
        "Bash(psql:*)",
        "Bash(mysql:*)",
        "Bash(mongo:*)",
        "Bash(mongosh:*)",
        "Bash(redis-cli:*)",

        // GitHub state-changing commands (reads via gh pr list / gh issue view stay ok)
        "Bash(gh pr create:*)",
        "Bash(gh pr merge:*)",
        "Bash(gh pr close:*)",
        "Bash(gh pr comment:*)",
        "Bash(gh pr edit:*)",
        "Bash(gh pr review:*)",
        "Bash(gh issue create:*)",
        "Bash(gh issue close:*)",
        "Bash(gh issue comment:*)",
        "Bash(gh issue edit:*)",
        "Bash(gh release create:*)",
        "Bash(gh release delete:*)",
        "Bash(gh api * -X POST:*)",
        "Bash(gh api * -X PUT:*)",
        "Bash(gh api * -X DELETE:*)",
        "Bash(gh api * -X PATCH:*)",

        // publish to package registries (state-changing)
        "Bash(npm publish:*)",
        "Bash(yarn publish:*)",
        "Bash(pnpm publish:*)",
        "Bash(pip upload:*)",
        "Bash(twine upload:*)",
        "Bash(cargo publish:*)",
        "Bash(gem push:*)",

        // MCP write-style tools (heuristic on common verb prefixes)
        "mcp__*__create_*",
        "mcp__*__delete_*",
        "mcp__*__update_*",
        "mcp__*__write_*",
        "mcp__*__send_*",
        "mcp__*__push_*",
        "mcp__*__remove_*",
        "mcp__*__post_*",
        "mcp__*__modify_*",
        "mcp__*__upload_*"
    ]

    /// True when `defaultMode` is bypass AND every allow/deny entry is present.
    static func isActive(in project: ClaudeProject) -> Bool {
        guard !project.isGlobal else { return false }
        let url = settingsURL(project: project)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let perms = (json["permissions"] as? [String: Any]) ?? [:]
        let mode = (perms["defaultMode"] as? String) ?? ""
        let currentAllow = Set((perms["allow"] as? [String]) ?? [])
        let currentDeny = Set((perms["deny"] as? [String]) ?? [])
        return mode == defaultMode
            && Set(allow).isSubset(of: currentAllow)
            && Set(deny).isSubset(of: currentDeny)
    }

    static func enable(in project: ClaudeProject) throws {
        guard !project.isGlobal else { return }
        try mutate(project: project) { settings in
            var perms = (settings["permissions"] as? [String: Any]) ?? [:]
            perms["defaultMode"] = defaultMode
            var allowList = (perms["allow"] as? [String]) ?? []
            for p in allow where !allowList.contains(p) { allowList.append(p) }
            perms["allow"] = allowList
            var denyList = (perms["deny"] as? [String]) ?? []
            for p in deny where !denyList.contains(p) { denyList.append(p) }
            perms["deny"] = denyList
            settings["permissions"] = perms
        }
    }

    static func disable(in project: ClaudeProject) throws {
        guard !project.isGlobal else { return }
        try mutate(project: project) { settings in
            var perms = (settings["permissions"] as? [String: Any]) ?? [:]
            if (perms["defaultMode"] as? String) == defaultMode {
                perms.removeValue(forKey: "defaultMode")
            }
            if var allowList = perms["allow"] as? [String] {
                let ours = Set(allow)
                allowList.removeAll { ours.contains($0) }
                perms["allow"] = allowList
            }
            if var denyList = perms["deny"] as? [String] {
                let ours = Set(deny)
                denyList.removeAll { ours.contains($0) }
                perms["deny"] = denyList
            }
            settings["permissions"] = perms
        }
    }

    private static func settingsURL(project: ClaudeProject) -> URL {
        project.url.appendingPathComponent(".claude/settings.local.json")
    }

    private static func mutate(project: ClaudeProject,
                               _ transform: (inout [String: Any]) -> Void) throws {
        let url = settingsURL(project: project)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = dict
        }
        transform(&settings)
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }
}
