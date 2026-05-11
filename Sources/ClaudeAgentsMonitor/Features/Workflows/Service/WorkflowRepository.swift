import Foundation

protocol WorkflowRepository {
    func loadAll() -> [Workflow]
    func save(name: String, description: String, triggers: [String],
              steps: String, graph: WorkflowGraph, overwrite: Bool) throws -> URL
    func delete(_ workflow: Workflow) throws
}

struct WorkflowRepositoryFile: WorkflowRepository {
    func loadAll() -> [Workflow] { WorkflowLoader.loadAll() }
    func save(name: String, description: String, triggers: [String],
              steps: String, graph: WorkflowGraph, overwrite: Bool) throws -> URL {
        try WorkflowWriter.save(name: name, description: description, triggers: triggers,
                                steps: steps, graph: graph, overwrite: overwrite)
    }
    func delete(_ workflow: Workflow) throws { try WorkflowWriter.delete(workflow) }
}
