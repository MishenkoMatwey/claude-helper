import Foundation
import CoreGraphics

enum WorkflowNodeKind: String, Codable, CaseIterable, Identifiable {
    case start, end, agent, gateway, parallel
    var id: String { rawValue }
}

struct WorkflowNode: Codable, Identifiable, Hashable {
    var id: String
    var kind: WorkflowNodeKind
    var x: Double
    var y: Double
    var label: String           // for agent: agent name; for gateway: condition expr
    var prompt: String          // for agent: prompt template; for gateway: e.g. "passed", regex
    var priority: Int           // higher = preferred when concurrent

    var position: CGPoint {
        get { CGPoint(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }
}

struct WorkflowEdge: Codable, Identifiable, Hashable {
    var id: String
    var from: String       // node id
    var to: String
    var condition: String  // "always" / "on pass" / "on fail" / custom regex
}

struct WorkflowGraph: Codable, Hashable {
    var nodes: [WorkflowNode]
    var edges: [WorkflowEdge]

    static let empty = WorkflowGraph(nodes: [], edges: [])

    static func newDefault() -> WorkflowGraph {
        WorkflowGraph(
            nodes: [
                WorkflowNode(id: "start", kind: .start, x: 80, y: 80, label: "Start", prompt: "", priority: 0),
                WorkflowNode(id: "end", kind: .end, x: 480, y: 80, label: "End", prompt: "", priority: 0)
            ],
            edges: []
        )
    }

    func node(_ id: String) -> WorkflowNode? {
        nodes.first { $0.id == id }
    }

    static func fromJSON(_ s: String) -> WorkflowGraph? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkflowGraph.self, from: data)
    }

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Renders the graph back into a markdown step list for the orchestrator to read.
    func toMarkdownSteps() -> String {
        guard !nodes.isEmpty else { return "" }
        var lines: [String] = ["## Steps", ""]
        // Sequential walk from start, expanding by edges.
        var visited: Set<String> = []
        let start = nodes.first { $0.kind == .start }?.id ?? nodes.first?.id ?? ""
        var stack: [String] = [start]
        var index = 0
        while let cur = stack.popLast() {
            guard !visited.contains(cur), let n = node(cur) else { continue }
            visited.insert(cur)
            let outgoing = edges.filter { $0.from == cur }
            switch n.kind {
            case .start:
                lines.append("**Start**")
            case .end:
                lines.append("**End**")
            case .agent:
                index += 1
                lines.append("\(index). **\(n.label)** — \(n.prompt.isEmpty ? "(no prompt)" : n.prompt)")
            case .gateway:
                lines.append("⊳ **Gateway**: \(n.label)")
                for e in outgoing {
                    if let target = node(e.to) {
                        lines.append("   - if `\(e.condition)` → \(target.label)")
                    }
                }
            case .parallel:
                lines.append("⫼ **Parallel branches** (priority highest first):")
                for e in outgoing {
                    if let target = node(e.to) {
                        lines.append("   - \(target.label) (priority \(target.priority))")
                    }
                }
            }
            for e in outgoing.sorted(by: { ($0.condition < $1.condition) }) {
                if !visited.contains(e.to) { stack.append(e.to) }
            }
        }
        return lines.joined(separator: "\n")
    }
}
