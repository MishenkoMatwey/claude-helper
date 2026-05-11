import Foundation

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let source: String   // "built-in" / "user" / "plugin:<plugin-name>"
    let path: URL?

    static func builtin(_ name: String, _ description: String) -> Skill {
        Skill(id: "built-in:\(name)", name: name, description: description, source: "built-in", path: nil)
    }
}

enum SkillLoader {
    /// Skills built into the Claude Code binary — not present on disk.
    private static let builtIns: [Skill] = [
        .builtin("init", "Initialize a CLAUDE.md file with codebase documentation"),
        .builtin("review", "Review a pull request"),
        .builtin("security-review", "Security review of pending changes on the current branch"),
        .builtin("simplify", "Review changed code for reuse, quality, efficiency; fix issues found"),
        .builtin("claude-api", "Build, debug, optimize Claude API / Anthropic SDK apps; migrate between Claude versions"),
        .builtin("loop", "Run a prompt or slash command on a recurring interval"),
        .builtin("schedule", "Create, update, list, or run scheduled remote agents (routines)"),
        .builtin("update-config", "Configure the Claude Code harness via settings.json (hooks, permissions, env vars)"),
        .builtin("keybindings-help", "Customize keyboard shortcuts in ~/.claude/keybindings.json"),
        .builtin("fewer-permission-prompts", "Add an allowlist to project settings to reduce permission prompts")
    ]

    static func loadAll() -> [Skill] {
        var skills: [Skill] = builtIns
        let home = FileManager.default.homeDirectoryForCurrentUser

        // User-level skills
        let userSkillsDir = home.appendingPathComponent(".claude/skills")
        skills.append(contentsOf: scanSkillRoot(userSkillsDir, source: "user"))

        // Plugin skills
        let pluginsDir = home.appendingPathComponent(".claude/plugins")
        if let enumerator = FileManager.default.enumerator(
            at: pluginsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator
                where url.lastPathComponent == "SKILL.md" {
                let pluginName = pluginName(forSkill: url) ?? "plugin"
                if let skill = parseSkill(at: url, source: "plugin:\(pluginName)") {
                    skills.append(skill)
                }
            }
        }

        // De-duplicate by name (prefer built-in > user > plugin).
        var seen: [String: Skill] = [:]
        for s in skills {
            if let existing = seen[s.name] {
                let rank: (Skill) -> Int = {
                    if $0.source == "built-in" { return 3 }
                    if $0.source == "user" { return 2 }
                    return 1
                }
                if rank(s) > rank(existing) { seen[s.name] = s }
            } else {
                seen[s.name] = s
            }
        }
        return seen.values.sorted { $0.name < $1.name }
    }

    private static func scanSkillRoot(_ dir: URL, source: String) -> [Skill] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        var out: [Skill] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let skillFile = entry.appendingPathComponent("SKILL.md")
                if FileManager.default.fileExists(atPath: skillFile.path),
                   let s = parseSkill(at: skillFile, source: source) {
                    out.append(s)
                }
            } else if entry.pathExtension == "md" {
                if let s = parseSkill(at: entry, source: source) {
                    out.append(s)
                }
            }
        }
        return out
    }

    private static func parseSkill(at url: URL, source: String) -> Skill? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let (frontmatter, _) = splitFrontmatter(raw)
        let fm = parseYAML(frontmatter)
        let name = fm["name"]
            ?? url.deletingLastPathComponent().lastPathComponent
        return Skill(
            id: "\(source):\(name)",
            name: name,
            description: fm["description"] ?? "",
            source: source,
            path: url
        )
    }

    private static func pluginName(forSkill url: URL) -> String? {
        // .../plugins/<plugin>/skills/<skill>/SKILL.md
        let parts = url.pathComponents
        if let idx = parts.firstIndex(of: "skills"), idx > 0 {
            return parts[idx - 1]
        }
        return nil
    }

    private static func splitFrontmatter(_ raw: String) -> (String, String) {
        guard raw.hasPrefix("---\n") else { return ("", raw) }
        let after = raw.dropFirst(4)
        guard let end = after.range(of: "\n---") else { return ("", raw) }
        return (String(after[..<end.lowerBound]), String(after[end.upperBound...]))
    }

    private static func parseYAML(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}
