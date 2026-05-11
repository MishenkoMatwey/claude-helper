import Foundation
import CoreGraphics

enum WorkflowLayout {
    /// Topological-tier layout. Places Start at left, End at right.
    /// Each tier = longest path from any source. Within tier, nodes spread vertically.
    static func autoLayout(_ graph: WorkflowGraph) -> WorkflowGraph {
        guard !graph.nodes.isEmpty else { return graph }
        var g = graph

        // Build adjacency
        var outgoing: [String: [String]] = [:]
        var incoming: [String: [String]] = [:]
        for e in g.edges {
            outgoing[e.from, default: []].append(e.to)
            incoming[e.to, default: []].append(e.from)
        }

        // Compute tier (longest path from any source). For nodes in cycles, fall back to BFS depth.
        var tier: [String: Int] = [:]
        let sources = g.nodes.filter { incoming[$0.id] == nil || incoming[$0.id]!.isEmpty }
        let actualSources = sources.isEmpty ? [g.nodes[0]] : sources
        var queue: [(String, Int)] = actualSources.map { ($0.id, 0) }
        var iterations = 0
        let maxIter = g.nodes.count * 4 + 1
        while !queue.isEmpty && iterations < maxIter {
            iterations += 1
            let (id, depth) = queue.removeFirst()
            let existing = tier[id] ?? -1
            if depth > existing {
                tier[id] = depth
                for next in outgoing[id] ?? [] {
                    queue.append((next, depth + 1))
                }
            }
        }
        // Any unvisited node — give them last+1 tier
        let maxTier = tier.values.max() ?? 0
        for n in g.nodes where tier[n.id] == nil {
            tier[n.id] = maxTier + 1
        }
        // If End is unreachable, push it to the last tier; otherwise its BFS tier is fine.
        for n in g.nodes where n.kind == .end {
            let currentMax = tier.values.max() ?? 0
            if (tier[n.id] ?? 0) < currentMax {
                tier[n.id] = currentMax
            }
        }

        // Group by tier
        var byTier: [Int: [WorkflowNode]] = [:]
        for n in g.nodes {
            let t = tier[n.id] ?? 0
            byTier[t, default: []].append(n)
        }

        // Layout
        let xSpacing: Double = 220
        let ySpacing: Double = 110
        let xOrigin: Double = 100
        let yOrigin: Double = 80

        let sortedTiers = byTier.keys.sorted()
        for tier in sortedTiers {
            let nodes = byTier[tier]!.sorted { $0.id < $1.id }
            let x = xOrigin + Double(tier) * xSpacing
            let totalH = Double(max(0, nodes.count - 1)) * ySpacing
            let yStart = yOrigin + max(0, (200 - totalH / 2))
            for (i, n) in nodes.enumerated() {
                if let idx = g.nodes.firstIndex(where: { $0.id == n.id }) {
                    g.nodes[idx].x = x
                    g.nodes[idx].y = yStart + Double(i) * ySpacing
                }
            }
        }
        return g
    }
}
