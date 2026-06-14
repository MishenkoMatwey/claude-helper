import Foundation

enum WorkflowWriterError: LocalizedError {
    case invalidName
    case alreadyExists(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Workflow name: only a-z, 0-9, hyphen."
        case .alreadyExists(let name): return "Workflow '\(name)' already exists."
        case .writeFailed(let msg): return "Failed to write: \(msg)"
        }
    }
}

enum WorkflowWriter {
    static func validate(name: String) -> Bool {
        name.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil
    }

    static func save(
        name: String,
        description: String,
        triggers: [String],
        steps: String,
        graph: WorkflowGraph = .empty,
        overwrite: Bool = false
    ) throws -> URL {
        guard validate(name: name) else { throw WorkflowWriterError.invalidName }

        let dir = WorkflowLoader.workflowsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("\(name).md")
        if !overwrite && FileManager.default.fileExists(atPath: url.path) {
            throw WorkflowWriterError.alreadyExists(name)
        }

        let triggersInline = triggers.isEmpty
            ? "[]"
            : "[" + triggers.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: ", ") + "]"

        // If a non-empty graph is provided, render the human-readable steps from it.
        let bodyText = graph.nodes.isEmpty ? steps : graph.toMarkdownSteps()

        let frontmatter = """
        ---
        name: \(name)
        description: \(description.replacingOccurrences(of: "\n", with: " "))
        triggers: \(triggersInline)
        ---

        """

        let content = frontmatter + bodyText + "\n"
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw WorkflowWriterError.writeFailed(error.localizedDescription)
        }

        // Sidecar graph JSON.
        let graphURL = dir.appendingPathComponent("\(name).graph.json")
        if graph.nodes.isEmpty {
            try? FileManager.default.removeItem(at: graphURL)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(graph) {
                try? data.write(to: graphURL)
            }
        }
        return url
    }

    static func delete(_ workflow: Workflow) throws {
        try FileManager.default.removeItem(at: workflow.filePath)
        let graphURL = workflow.filePath.deletingLastPathComponent()
            .appendingPathComponent("\(workflow.name).graph.json")
        try? FileManager.default.removeItem(at: graphURL)
    }
}
