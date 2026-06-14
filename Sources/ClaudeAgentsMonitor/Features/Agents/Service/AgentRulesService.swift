import Foundation

/// Loads/saves agent rules from/to a single rules.yaml file.
///
/// The on-disk format is YAML, but we only support the narrow schema described
/// in `rules.yaml` templates. The parser/writer here is hand-rolled — no PyYAML,
/// no external dependency. Anything fancier than scalar fields + `|` blocks
/// goes through a single-string fallback (still survives a round-trip).
enum AgentRulesService {

    // MARK: - Public

    static func load(from url: URL) -> [AgentRule] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func save(_ rules: [AgentRule], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let header = """
        # Правила для агента. Поле id — стабильный slug, остальное редактируется свободно.
        # Сгенерировано/сохранено через CAM. Формат описан в шаблоне миграции.
        """
        let body = dump(rules)
        try (header + "\n" + body).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Parser

    /// Minimal YAML parser tailored to our schema.
    static func parse(_ text: String) -> [AgentRule] {
        let lines = text.components(separatedBy: "\n")
        var i = 0
        // Skip until `rules:` line
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "rules:" || trimmed.hasPrefix("rules: ") {
                break
            }
            i += 1
        }
        if i >= lines.count { return [] }
        if lines[i].trimmingCharacters(in: .whitespaces) == "rules: []" { return [] }
        i += 1

        var rules: [AgentRule] = []
        var current: [String: String] = [:]
        var multilineKey: String?
        var multilineBuffer: [String] = []
        var multilineIndent: Int?

        func flushMultiline() {
            if let key = multilineKey {
                let joined = multilineBuffer.joined(separator: "\n")
                current[key] = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            multilineKey = nil
            multilineBuffer.removeAll()
            multilineIndent = nil
        }

        func flushRule() {
            if !current.isEmpty {
                rules.append(ruleFromDict(current))
                current.removeAll()
            }
        }

        while i < lines.count {
            let raw = lines[i]
            let stripped = raw.trimmingCharacters(in: .whitespaces)

            // Multiline scalar block: collect lines with indent >= multilineIndent.
            if multilineKey != nil {
                if stripped.isEmpty {
                    multilineBuffer.append("")
                    i += 1
                    continue
                }
                let indent = raw.prefix { $0 == " " }.count
                if multilineIndent == nil { multilineIndent = indent }
                if indent >= (multilineIndent ?? 0) {
                    let cut = max(0, multilineIndent ?? 0)
                    let payload = String(raw.dropFirst(cut))
                    multilineBuffer.append(payload)
                    i += 1
                    continue
                }
                flushMultiline()
                // re-read current line as a regular field/list entry
                continue
            }

            if stripped.isEmpty || stripped.hasPrefix("#") {
                i += 1
                continue
            }

            // List entry: "- key: value"
            if stripped.hasPrefix("- ") {
                flushRule()
                let body = String(stripped.dropFirst(2))
                if let colon = body.firstIndex(of: ":") {
                    let k = String(body[..<colon]).trimmingCharacters(in: .whitespaces)
                    let v = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    setField(&current, key: k, raw: v,
                             startMultiline: { ml in
                                 multilineKey = k
                                 multilineBuffer.removeAll()
                                 multilineIndent = nil
                                 _ = ml
                             })
                }
                i += 1
                continue
            }

            // Plain field: "key: value"
            if let colon = stripped.firstIndex(of: ":") {
                let k = String(stripped[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(stripped[stripped.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if v == "|" || v == "|-" {
                    multilineKey = k
                    multilineBuffer.removeAll()
                    multilineIndent = nil
                } else {
                    setField(&current, key: k, raw: v, startMultiline: { _ in })
                }
            }
            i += 1
        }
        flushMultiline()
        flushRule()
        return rules
    }

    private static func setField(
        _ dict: inout [String: String],
        key: String,
        raw: String,
        startMultiline: (Bool) -> Void
    ) {
        var v = raw
        if v == "|" || v == "|-" {
            startMultiline(true)
            return
        }
        if v.count >= 2 {
            let first = v.first!
            let last = v.last!
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                v = String(v.dropFirst().dropLast())
                if first == "\"" {
                    v = v.replacingOccurrences(of: "\\\"", with: "\"")
                }
            }
        }
        dict[key] = v
    }

    private static func ruleFromDict(_ d: [String: String]) -> AgentRule {
        let severity = RuleSeverity(rawValue: (d["severity"] ?? "").lowercased()) ?? .major
        return AgentRule(
            id: d["id"] ?? "",
            severity: severity,
            category: d["category"] ?? "",
            title: d["title"] ?? "",
            pattern: d["pattern"] ?? "",
            example: d["example"] ?? "",
            rationale: d["rationale"] ?? "",
            fix: d["fix"] ?? ""
        )
    }

    // MARK: - Writer

    static func dump(_ rules: [AgentRule]) -> String {
        if rules.isEmpty {
            return "rules: []\n"
        }
        var out = "rules:\n"
        let fieldsOrder: [(String, (AgentRule) -> String)] = [
            ("id", { $0.id }),
            ("severity", { $0.severity.rawValue }),
            ("category", { $0.category }),
            ("title", { $0.title }),
            ("pattern", { $0.pattern }),
            ("example", { $0.example }),
            ("rationale", { $0.rationale }),
            ("fix", { $0.fix })
        ]
        for rule in rules {
            var firstField = true
            for (key, getter) in fieldsOrder {
                let value = getter(rule)
                if value.isEmpty && key != "id" && key != "severity" { continue }
                let prefix = firstField ? "  - " : "    "
                firstField = false
                if value.contains("\n") {
                    out += "\(prefix)\(key): |\n"
                    for line in value.components(separatedBy: "\n") {
                        out += "      \(line)\n"
                    }
                } else {
                    out += "\(prefix)\(key): \(quoteIfNeeded(value))\n"
                }
            }
            out += "\n"
        }
        return out
    }

    private static func quoteIfNeeded(_ v: String) -> String {
        if v.isEmpty { return "\"\"" }
        // YAML special chars at start or content containing `:` / `#` → quote.
        let needsQuote: Bool = {
            if let first = v.first {
                if "-?:[]{},&*!|>'\"%@`".contains(first) { return true }
            }
            if v.contains(": ") || v.contains(" #") { return true }
            return false
        }()
        if !needsQuote { return v }
        let escaped = v.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
