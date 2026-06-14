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

    /// Renders the graph into a markdown step list. Round-trippable with `WorkflowGraphParser.parse`.
    ///
    /// Format:
    /// ```
    /// ## Steps
    ///
    /// ### Start — <id>
    ///
    /// ### Step <N> — <agent-name> [id=<node-id>]
    /// **Prompt:**
    /// <prompt body>
    ///
    /// ### Gateway — <label> [id=<node-id>]
    /// - if `<condition>` → <target-id>
    /// - if `<condition>` → <target-id>
    ///
    /// ### Parallel — <label> [id=<node-id>]
    /// - <target-id> (priority <N>)
    ///
    /// ### End — <id> (<label>)
    /// ```
    func toMarkdownSteps() -> String {
        guard !nodes.isEmpty else { return "" }

        var lines: [String] = ["## Steps", ""]

        // Walk graph in deterministic order: start → BFS through outgoing edges.
        var order: [String] = []
        var visited: Set<String> = []
        let starts = nodes.filter { $0.kind == .start }
        var queue: [String] = starts.map(\.id)
        if queue.isEmpty, let first = nodes.first { queue = [first.id] }

        while !queue.isEmpty {
            let cur = queue.removeFirst()
            guard !visited.contains(cur), node(cur) != nil else { continue }
            visited.insert(cur)
            order.append(cur)
            let outs = edges.filter { $0.from == cur }
                .sorted { ($0.condition, $0.to) < ($1.condition, $1.to) }
            for e in outs where !visited.contains(e.to) {
                queue.append(e.to)
            }
        }
        // Append any disconnected nodes after the connected walk.
        for n in nodes where !visited.contains(n.id) {
            order.append(n.id)
        }

        var stepIndex = 0
        for id in order {
            guard let n = node(id) else { continue }
            let outs = edges.filter { $0.from == id }
                .sorted { ($0.condition, $0.to) < ($1.condition, $1.to) }
            switch n.kind {
            case .start:
                lines.append("### Start — \(n.id)")
                lines.append("")
            case .end:
                let labelSuffix = n.label.isEmpty || n.label == "End" ? "" : " (\(n.label))"
                lines.append("### End — \(n.id)\(labelSuffix)")
                lines.append("")
            case .agent:
                stepIndex += 1
                let agentName = n.label.isEmpty ? "agent" : n.label
                lines.append("### Step \(stepIndex) — \(agentName) [id=\(n.id)]")
                if !n.prompt.isEmpty {
                    lines.append("**Prompt:**")
                    lines.append(n.prompt)
                }
                lines.append("")
            case .gateway:
                let label = n.label.isEmpty ? "decision" : n.label
                lines.append("### Gateway — \(label) [id=\(n.id)]")
                for e in outs {
                    lines.append("- if `\(e.condition)` → \(e.to)")
                }
                lines.append("")
            case .parallel:
                let label = n.label.isEmpty ? "parallel" : n.label
                lines.append("### Parallel — \(label) [id=\(n.id)]")
                for e in outs {
                    let target = node(e.to)
                    let prio = target?.priority ?? 0
                    lines.append("- \(e.to) (priority \(prio))")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
