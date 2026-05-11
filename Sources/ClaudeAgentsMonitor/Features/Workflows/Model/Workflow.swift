import Foundation

struct Workflow: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let triggers: [String]
    let steps: String          // markdown body — list of steps
    let graph: WorkflowGraph
    let filePath: URL

    var triggersSummary: String {
        triggers.prefix(3).map { "\"\($0)\"" }.joined(separator: ", ")
    }
}
