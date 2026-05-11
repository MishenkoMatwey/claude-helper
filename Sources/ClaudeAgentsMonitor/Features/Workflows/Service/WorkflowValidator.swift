import Foundation

struct ValidationIssue: Identifiable, Hashable {
    let id = UUID()
    let severity: Severity
    let message: String
    let nodeId: String?
    let edgeId: String?

    enum Severity: String { case error, warning, info }
}

enum WorkflowValidator {
    static func validate(_ graph: WorkflowGraph, agents: [Agent]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // 1. Missing start / end
        let starts = graph.nodes.filter { $0.kind == .start }
        let ends = graph.nodes.filter { $0.kind == .end }
        if starts.isEmpty {
            issues.append(.init(severity: .error, message: "Нет Start-блока", nodeId: nil, edgeId: nil))
        }
        if starts.count > 1 {
            for s in starts.dropFirst() {
                issues.append(.init(severity: .warning, message: "Несколько Start-блоков (используется первый)", nodeId: s.id, edgeId: nil))
            }
        }
        if ends.isEmpty {
            issues.append(.init(severity: .warning, message: "Нет End-блока — не понятно когда workflow закончен", nodeId: nil, edgeId: nil))
        }

        // 2. Build adjacency
        var outgoing: [String: [String]] = [:]
        var incoming: [String: [String]] = [:]
        let nodeIds = Set(graph.nodes.map(\.id))
        for e in graph.edges {
            if !nodeIds.contains(e.from) {
                issues.append(.init(severity: .error, message: "Edge ссылается на несуществующий source '\(e.from)'", nodeId: nil, edgeId: e.id))
            }
            if !nodeIds.contains(e.to) {
                issues.append(.init(severity: .error, message: "Edge ссылается на несуществующий target '\(e.to)'", nodeId: nil, edgeId: e.id))
            }
            outgoing[e.from, default: []].append(e.to)
            incoming[e.to, default: []].append(e.from)
        }

        // 3. Orphan nodes (нет ни in, ни out)
        for n in graph.nodes where n.kind != .start && n.kind != .end {
            let hasIn = !(incoming[n.id]?.isEmpty ?? true)
            let hasOut = !(outgoing[n.id]?.isEmpty ?? true)
            if !hasIn && !hasOut {
                issues.append(.init(severity: .warning, message: "Orphan: '\(n.label)' не подключён", nodeId: n.id, edgeId: nil))
            } else if !hasIn {
                issues.append(.init(severity: .warning, message: "'\(n.label)' не имеет входящих edges (недостижим)", nodeId: n.id, edgeId: nil))
            } else if !hasOut {
                issues.append(.init(severity: .warning, message: "'\(n.label)' не имеет исходящих edges (deadend, кроме End)", nodeId: n.id, edgeId: nil))
            }
        }

        // 4. Reachability from Start
        if let start = starts.first {
            var visited: Set<String> = []
            var queue: [String] = [start.id]
            while let cur = queue.popLast() {
                guard !visited.contains(cur) else { continue }
                visited.insert(cur)
                for next in outgoing[cur] ?? [] {
                    queue.append(next)
                }
            }
            for n in graph.nodes where !visited.contains(n.id) && n.kind != .start {
                issues.append(.init(severity: .warning, message: "'\(n.label)' недостижим из Start", nodeId: n.id, edgeId: nil))
            }
        }

        // 5. Cycle detection (DFS with recursion stack)
        var color: [String: Int] = [:] // 0=white,1=gray,2=black
        for n in graph.nodes { color[n.id] = 0 }
        var cycles: [(String, String)] = []
        func dfs(_ id: String, parent: String?) {
            color[id] = 1
            for next in outgoing[id] ?? [] {
                if (color[next] ?? 0) == 1 {
                    cycles.append((id, next))
                } else if (color[next] ?? 0) == 0 {
                    dfs(next, parent: id)
                }
            }
            color[id] = 2
        }
        for n in graph.nodes where (color[n.id] ?? 0) == 0 {
            dfs(n.id, parent: nil)
        }
        for (from, to) in cycles {
            let fromLabel = graph.node(from)?.label ?? from
            let toLabel = graph.node(to)?.label ?? to
            issues.append(.init(severity: .error, message: "Цикл: '\(fromLabel)' → '\(toLabel)'", nodeId: from, edgeId: nil))
        }

        // 6. Empty agent labels / unknown agents
        let knownAgentNames = Set(agents.map(\.name))
        for n in graph.nodes where n.kind == .agent {
            if n.label.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(.init(severity: .error, message: "Agent-блок без выбранного агента", nodeId: n.id, edgeId: nil))
            } else if !knownAgentNames.contains(n.label) && n.label != "agent" {
                issues.append(.init(severity: .warning, message: "Агент '\(n.label)' не существует — создай через UI", nodeId: n.id, edgeId: nil))
            }
        }

        // 7. Gateway without multiple outgoing
        for n in graph.nodes where n.kind == .gateway {
            let count = outgoing[n.id]?.count ?? 0
            if count < 2 {
                issues.append(.init(severity: .warning, message: "Gateway '\(n.label)' имеет <2 исходящих edges — смысл потерян", nodeId: n.id, edgeId: nil))
            }
        }

        // 8. Duplicate edges
        var pairs: [String: Int] = [:]
        for e in graph.edges {
            let key = "\(e.from)→\(e.to)"
            pairs[key, default: 0] += 1
        }
        for (key, count) in pairs where count > 1 {
            issues.append(.init(severity: .info, message: "Дубликат edge: \(key) (×\(count))", nodeId: nil, edgeId: nil))
        }

        return issues
    }
}
