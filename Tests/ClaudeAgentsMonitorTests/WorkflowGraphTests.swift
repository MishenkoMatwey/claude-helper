import Testing
import Foundation
@testable import ClaudeAgentsMonitor

@Suite("WorkflowGraph")
struct WorkflowGraphTests {
    @Test("newDefault has Start and End")
    func newDefault() {
        let graph = WorkflowGraph.newDefault()
        #expect(graph.nodes.count == 2)
        #expect(graph.nodes.contains { $0.kind == .start })
        #expect(graph.nodes.contains { $0.kind == .end })
        #expect(graph.edges.isEmpty)
    }

    @Test("JSON round-trip preserves nodes and edges")
    func jsonRoundTrip() {
        var graph = WorkflowGraph.newDefault()
        graph.nodes.append(WorkflowNode(
            id: "n1", kind: .agent, x: 250, y: 100,
            label: "dev", prompt: "do stuff", priority: 5
        ))
        graph.edges.append(WorkflowEdge(
            id: "e1", from: "start", to: "n1", condition: "always"
        ))
        let json = graph.toJSON()
        let parsed = WorkflowGraph.fromJSON(json)
        #expect(parsed?.nodes.count == 3)
        #expect(parsed?.edges.count == 1)
        #expect(parsed?.node("n1")?.label == "dev")
    }

    @Test("Node lookup by id")
    func nodeLookup() {
        let graph = WorkflowGraph.newDefault()
        #expect(graph.node("start")?.kind == .start)
        #expect(graph.node("missing") == nil)
    }

    @Test("Markdown steps render")
    func markdownSteps() {
        var graph = WorkflowGraph.newDefault()
        graph.nodes.append(WorkflowNode(
            id: "n1", kind: .agent, x: 0, y: 0, label: "dev", prompt: "task", priority: 0
        ))
        graph.edges.append(WorkflowEdge(id: "e1", from: "start", to: "n1", condition: "always"))
        let md = graph.toMarkdownSteps()
        #expect(md.contains("**Start**"))
        #expect(md.contains("**dev**"))
    }
}
