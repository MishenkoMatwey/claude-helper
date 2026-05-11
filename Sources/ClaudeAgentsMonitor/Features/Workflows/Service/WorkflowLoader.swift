import Foundation

enum WorkflowLoader {
    static func workflowsDirectory() -> URL {
        AgentLoader.agentsDirectory().appendingPathComponent("workflows")
    }

    static func loadAll() -> [Workflow] {
        let dir = workflowsDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "md" }
            .compactMap(parse(file:))
            .sorted { $0.name < $1.name }
    }

    static func parse(file: URL) -> Workflow? {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let (frontmatter, body) = splitFrontmatter(raw)
        let fm = parseYAML(frontmatter)
        let name = fm["name"] ?? file.deletingPathExtension().lastPathComponent
        let triggers = parseList(fm["triggers"])
        let graphURL = file.deletingLastPathComponent()
            .appendingPathComponent("\(name).graph.json")
        let graph: WorkflowGraph = (try? Data(contentsOf: graphURL))
            .flatMap { try? JSONDecoder().decode(WorkflowGraph.self, from: $0) }
            ?? .empty
        return Workflow(
            id: name,
            name: name,
            description: fm["description"] ?? "",
            triggers: triggers,
            steps: body.trimmingCharacters(in: .whitespacesAndNewlines),
            graph: graph,
            filePath: file
        )
    }

    private static func splitFrontmatter(_ raw: String) -> (String, String) {
        guard raw.hasPrefix("---\n") else { return ("", raw) }
        let after = raw.dropFirst(4)
        guard let end = after.range(of: "\n---\n") else { return ("", raw) }
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

    /// Triggers can be written as a comma-separated list inside square brackets:
    /// `triggers: ["commit", "закоммить", "ship it"]`
    private static func parseList(_ raw: String?) -> [String] {
        guard var s = raw else { return [] }
        if s.hasPrefix("[") && s.hasSuffix("]") {
            s = String(s.dropFirst().dropLast())
        }
        return s
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: "\""))) }
            .filter { !$0.isEmpty }
    }
}
