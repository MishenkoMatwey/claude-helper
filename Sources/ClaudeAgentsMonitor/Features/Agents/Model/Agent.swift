import Foundation

struct Agent: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let tools: [String]
    let model: String?
    let systemPrompt: String
    let attachedSkills: [String]
    let filePath: URL
    let memoryPath: URL?
    /// Optional user-chosen icon override. Format: bundled brand-asset name
    /// (`git`, `jira`, `confluence`, `figma`, `database`, `github`, `gitlab`).
    var iconAsset: String?
    /// SF Symbol fallback if `iconAsset` is nil or asset missing.
    var iconSymbol: String?
    /// Color key — `orange`, `purple`, `blue`, `green`, `red`, `gray`.
    var iconColor: String?
    /// Optional role marker from frontmatter `role:`. Used to flag the agent as an
    /// orchestrator regardless of file name (`role: orchestrator`).
    var role: String?

    /// True if this agent should be treated as the project's orchestrator —
    /// either its file is named `orchestrator.md`, or its frontmatter declares `role: orchestrator`.
    var isOrchestrator: Bool {
        name == OrchestratorBuilder.agentName || role?.lowercased() == "orchestrator"
    }

    /// True if the agent file lives outside `~/.claude/agents/` — i.e. it's project-scoped
    /// rather than user-global. Used when picking the active orchestrator: project beats user.
    var isProjectScope: Bool {
        let userAgents = NSHomeDirectory() + "/.claude/agents/"
        return !filePath.path.hasPrefix(userAgents)
    }

    var permissionsSummary: String {
        tools.isEmpty ? "all tools" : tools.joined(separator: ", ")
    }

    /// System prompt without auto-injected blocks (Memory + Variables + Skills).
    var promptWithoutInjectedBlocks: String {
        var s = systemPrompt
        for marker in [
            "\n\n## Memory protocol",
            "\n\n## Память",
            "\n\n## Variables & Secrets",
            "\n\n## Available skills"
        ] {
            if let range = s.range(of: marker) {
                s = String(s[..<range.lowerBound])
            }
        }
        return s
    }
}

extension Array where Element == Agent {
    /// Returns the active orchestrator, preferring project-scope over user-global so a renamed
    /// project orchestrator (e.g. `orchestrator-clussters`) takes precedence over the default.
    func activeOrchestrator() -> Agent? {
        let orchs = filter { $0.isOrchestrator }
        return orchs.first(where: \.isProjectScope) ?? orchs.first
    }
}
