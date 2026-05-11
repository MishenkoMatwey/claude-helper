import Foundation

enum AgentLoader {
    static func agentsDirectory() -> URL {
        AgentPaths.current.agentsRoot
    }

    static func loadAll() -> [Agent] {
        let dir = agentsDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "md" }
            .compactMap(parse(file:))
            .sorted { $0.name < $1.name }
    }

    static func parse(file: URL) -> Agent? {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let (frontmatter, body) = splitFrontmatter(raw)
        let fm = parseYAML(frontmatter)
        let name = fm["name"] ?? file.deletingPathExtension().lastPathComponent
        let memory = file.deletingLastPathComponent()
            .appendingPathComponent("memory/\(name).md")
        let bodyTrimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let skills = extractSkills(from: bodyTrimmed)
        return Agent(
            id: name,
            name: name,
            description: fm["description"] ?? "",
            tools: (fm["tools"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            model: fm["model"],
            systemPrompt: bodyTrimmed,
            attachedSkills: skills,
            filePath: file,
            memoryPath: FileManager.default.fileExists(atPath: memory.path) ? memory : nil
        )
    }

    private static func extractSkills(from prompt: String) -> [String] {
        guard let range = prompt.range(of: "## Available skills") else { return [] }
        let block = prompt[range.upperBound...]
        var names: [String] = []
        for line in block.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- **") else { continue }
            let after = trimmed.dropFirst(4)
            if let end = after.range(of: "**") {
                names.append(String(after[..<end.lowerBound]))
            }
        }
        return names
    }

    private static func splitFrontmatter(_ raw: String) -> (String, String) {
        guard raw.hasPrefix("---\n") else { return ("", raw) }
        let after = raw.dropFirst(4)
        guard let end = after.range(of: "\n---\n") else { return ("", raw) }
        let fm = String(after[..<end.lowerBound])
        let body = String(after[end.upperBound...])
        return (fm, body)
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
