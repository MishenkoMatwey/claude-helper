import Foundation

/// Renames an agent end-to-end: .md, sibling memory files, .schema.md, .vars.json,
/// Keychain service prefix, `Edit(...)` paths in tools allowlist, and `<old>.<suf>` mentions
/// inside the system prompt.
enum AgentRename {

    enum RenameError: LocalizedError {
        case targetExists(String)
        var errorDescription: String? {
            switch self {
            case .targetExists(let name): return "Agent '\(name)' already exists — pick a different name."
            }
        }
    }

    /// Move files + re-key Keychain. Returns silently if `from == to`.
    static func renameArtifacts(from old: String, to new: String, agentsDir: URL) throws {
        guard old != new else { return }
        let fm = FileManager.default
        let memDir = agentsDir.appendingPathComponent("memory")

        let srcMd = agentsDir.appendingPathComponent("\(old).md")
        let dstMd = agentsDir.appendingPathComponent("\(new).md")
        if fm.fileExists(atPath: dstMd.path) {
            throw RenameError.targetExists(new)
        }
        if fm.fileExists(atPath: srcMd.path) {
            try fm.moveItem(at: srcMd, to: dstMd)
        }

        for suf in [".md", ".playbooks.md", ".context.md", ".vars.json", ".schema.md"] {
            let src = memDir.appendingPathComponent("\(old)\(suf)")
            let dst = memDir.appendingPathComponent("\(new)\(suf)")
            if fm.fileExists(atPath: src.path) {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.moveItem(at: src, to: dst)
            }
            if suf == ".schema.md" {
                // .schema.md may sit next to .md, not in memory/
                let s = agentsDir.appendingPathComponent("\(old)\(suf)")
                let d = agentsDir.appendingPathComponent("\(new)\(suf)")
                if fm.fileExists(atPath: s.path) {
                    if fm.fileExists(atPath: d.path) { try fm.removeItem(at: d) }
                    try fm.moveItem(at: s, to: d)
                }
            }
        }

        let oldSvc = AgentVariablesService.keychainService(for: old)
        let newSvc = AgentVariablesService.keychainService(for: new)
        for key in AgentVariablesService.listKeychainKeys(service: oldSvc) {
            if let value = AgentVariablesService.readKeychain(key: key, service: oldSvc) {
                try? AgentVariablesService.saveKeychain(key: key, value: value, service: newSvc)
                try? AgentVariablesService.removeKeychain(key: key, service: oldSvc)
            }
        }
    }

    /// Returns a copy of `tools` with `Edit(.../<old>.<suf>)` substrings rewritten to `<new>`.
    static func rewriteTools(_ tools: [String], from old: String, to new: String,
                             memDir: URL) -> [String] {
        guard old != new else { return tools }
        let suffixes = [".md", ".playbooks.md", ".context.md", ".vars.json", ".schema.md"]
        let memPath = memDir.path
        return tools.map { t in
            var s = t
            for suf in suffixes {
                s = s.replacingOccurrences(of: "\(memPath)/\(old)\(suf)",
                                           with: "\(memPath)/\(new)\(suf)")
            }
            return s
        }
    }

    /// Replace `<old>.<suf>` occurrences and `(<old>)` mentions inside the (already
    /// stripped of auto-blocks) system prompt.
    static func rewritePrompt(_ prompt: String, from old: String, to new: String) -> String {
        guard old != new else { return prompt }
        var s = prompt
        for suf in [".md", ".playbooks.md", ".context.md", ".vars.json", ".schema.md"] {
            s = s.replacingOccurrences(of: "\(old)\(suf)", with: "\(new)\(suf)")
        }
        s = s.replacingOccurrences(of: "(\(old))", with: "(\(new))")
        return s
    }

    /// After AgentWriter.save (without icon-* params), inject icon-asset / icon-symbol /
    /// icon-color lines into the file's frontmatter (or strip them if all nil).
    static func patchIconFrontmatter(at url: URL,
                                     iconAsset: String?,
                                     iconSymbol: String?,
                                     iconColor: String?) throws {
        var src = try String(contentsOf: url, encoding: .utf8)
        for p in ["\nicon-asset: .*", "\nicon-symbol: .*", "\nicon-color: .*"] {
            if let r = try? NSRegularExpression(pattern: p) {
                let range = NSRange(src.startIndex..., in: src)
                src = r.stringByReplacingMatches(in: src, range: range, withTemplate: "")
            }
        }
        var lines: [String] = []
        if let v = iconAsset?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            lines.append("icon-asset: \(v)")
        }
        if let v = iconSymbol?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            lines.append("icon-symbol: \(v)")
        }
        if let v = iconColor?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            lines.append("icon-color: \(v)")
        }
        if !lines.isEmpty,
           let openRange = src.range(of: "---\n"),
           let closeRange = src.range(of: "\n---\n", range: openRange.upperBound..<src.endIndex) {
            let inject = "\n" + lines.joined(separator: "\n")
            src.insert(contentsOf: inject, at: closeRange.lowerBound)
        }
        try src.write(to: url, atomically: true, encoding: .utf8)
    }
}
