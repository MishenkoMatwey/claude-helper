import Foundation

/// One-time import of v2 file-based memory into the v3 SQLite store.
///
/// Maps:
///   context.md   → `fact`     notes (one per `## section`)
///   rules.yaml   → `rule`     notes
///   playbooks.md → `playbook` notes (one per `## name`)
///   log.md       → `session`  notes (one per `## …` entry, tags from `[#topic]`)
///
/// `vars.json` is intentionally left in place — variables keep their own UI/keychain.
/// After a successful import the source files are moved to `memory/_v2_backup/`,
/// which also makes the migration idempotent (sources gone → nothing to do).
enum MemoryMigration {
    struct Source {
        var context: URL?
        var rules: URL?
        var playbooks: URL?
        var log: URL?

        var isEmpty: Bool { context == nil && rules == nil && playbooks == nil && log == nil }
        var count: Int { [context, rules, playbooks, log].compactMap { $0 }.count }
        var all: [URL] { [context, rules, playbooks, log].compactMap { $0 } }
    }

    /// Locate existing v2 files for an agent (canonical subdir layout, falling back
    /// to the older flat dotted layout). Only returns paths that actually exist.
    static func sources(agent: String, paths: AgentPaths) -> Source {
        let mem = paths.memoryDir
        let subdir = mem.appendingPathComponent(agent)
        let fm = FileManager.default

        func pick(_ sub: String, _ flat: String) -> URL? {
            let a = subdir.appendingPathComponent(sub)
            if fm.fileExists(atPath: a.path) { return a }
            let b = mem.appendingPathComponent(flat)
            return fm.fileExists(atPath: b.path) ? b : nil
        }

        return Source(
            context: pick("context.md", "\(agent).context.md"),
            rules: pick("rules.yaml", "\(agent).rules.yaml"),
            playbooks: pick("playbooks.md", "\(agent).playbooks.md"),
            log: pick("log.md", "\(agent).md")
        )
    }

    /// Run the import. Returns the number of notes created. No-op if no sources.
    @discardableResult
    static func migrate(agent: String, store: MemoryStore, paths: AgentPaths) throws -> Int {
        let src = sources(agent: agent, paths: paths)
        guard !src.isEmpty else { return 0 }

        var created = 0

        if let url = src.context, let text = try? String(contentsOf: url, encoding: .utf8) {
            for sec in sections(in: text) {
                guard !sec.body.isEmpty else { continue }
                try store.save(MemoryNote(agent: agent, kind: .fact,
                                          title: sec.title, body: sec.body, tags: ["context"]))
                created += 1
            }
        }

        if let url = src.rules {
            for rule in AgentRulesService.load(from: url) {
                let title = rule.title.isEmpty ? rule.id : rule.title
                var lines: [String] = []
                if !rule.pattern.isEmpty { lines.append("**Pattern:** \(rule.pattern)") }
                if !rule.rationale.isEmpty { lines.append("**Why:** \(rule.rationale)") }
                if !rule.fix.isEmpty { lines.append("**Fix:** \(rule.fix)") }
                if !rule.example.isEmpty { lines.append("**Example:**\n\(rule.example)") }
                var tags = ["rule"]
                if !rule.category.isEmpty { tags.append(rule.category) }
                try store.save(MemoryNote(agent: agent, kind: .rule,
                                          title: title,
                                          body: lines.joined(separator: "\n"), tags: tags))
                created += 1
            }
        }

        if let url = src.playbooks, let text = try? String(contentsOf: url, encoding: .utf8) {
            for sec in sections(in: text) {
                guard !sec.body.isEmpty else { continue }
                try store.save(MemoryNote(agent: agent, kind: .playbook,
                                          title: sec.title, body: sec.body, tags: ["playbook"]))
                created += 1
            }
        }

        if let url = src.log, let text = try? String(contentsOf: url, encoding: .utf8) {
            for sec in sections(in: text) {
                guard !sec.body.isEmpty || sec.title.contains("—") else { continue }
                let (title, tags) = parseSessionHeading(sec.title)
                try store.save(MemoryNote(agent: agent, kind: .session,
                                          title: title, body: sec.body,
                                          tags: tags.isEmpty ? ["session"] : tags))
                created += 1
            }
        }

        // Move sources to backup so we never re-import.
        try backup(src.all, agent: agent, paths: paths)
        return created
    }

    /// Migrate every agent in the current namespace. Returns (agents, notes).
    @discardableResult
    static func migrateAll(paths: AgentPaths) -> (agents: Int, notes: Int) {
        let store: MemoryStore
        do {
            store = try MemoryStore(path: paths.memoryDBFile)
        } catch {
            return (0, 0)
        }
        var agents = 0, notes = 0
        for agent in AgentLoader.loadAll() {
            let n = (try? migrate(agent: agent.name, store: store, paths: paths)) ?? 0
            if n > 0 { agents += 1; notes += n }
        }
        return (agents, notes)
    }

    /// CLI entry (`--migrate-all [--project <path>]`). Defaults to the global namespace.
    static func migrateAllCLI() {
        AgentPaths.current = AgentCLIScope.resolve()
        let r = migrateAll(paths: .current)
        print("✅ migrate-all [\(AgentPaths.current.projectName)]: \(r.agents) agents, \(r.notes) notes")
    }

    // MARK: - Markdown section splitting

    struct MDSection { var title: String; var body: String }

    /// Split markdown into `## ` sections. A leading `# H1` and any preamble before
    /// the first `## ` are dropped.
    static func sections(in text: String) -> [MDSection] {
        var result: [MDSection] = []
        var current: MDSection?
        for raw in text.components(separatedBy: "\n") {
            if raw.hasPrefix("## ") {
                if let c = current { result.append(trim(c)) }
                current = MDSection(title: String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces), body: "")
            } else if current != nil {
                current!.body += raw + "\n"
            }
        }
        if let c = current { result.append(trim(c)) }
        return result
    }

    private static func trim(_ s: MDSection) -> MDSection {
        MDSection(title: s.title,
                  body: s.body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `2026-06-14 12:00 — ревью auth [#auth #api]` → ("2026-06-14 12:00 — ревью auth", ["auth","api"]).
    static func parseSessionHeading(_ heading: String) -> (title: String, tags: [String]) {
        var tags: [String] = []
        var title = heading
        if let open = heading.lastIndex(of: "["), let close = heading.lastIndex(of: "]"), open < close {
            let inside = heading[heading.index(after: open)..<close]
            tags = inside.split(separator: " ").map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            }.filter { !$0.isEmpty }
            title = String(heading[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return (title, tags)
    }

    // MARK: - Backup

    private static func backup(_ urls: [URL], agent: String, paths: AgentPaths) throws {
        let fm = FileManager.default
        let dir = paths.memoryDir.appendingPathComponent("_v2_backup").appendingPathComponent(agent)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in urls {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: url, to: dest)
        }
    }
}
