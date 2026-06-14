import SwiftUI

/// Lightweight graph of memory notes and their links.
/// Nodes laid out on a circle (deterministic, no physics); edges drawn as lines.
/// Tapping a node calls `onSelect` with its id. Good enough to *see* the structure
/// without pulling in a force-directed layout dependency.
struct MemoryGraphView: View {
    let notes: [MemoryNote]
    let edges: [MemoryEdge]
    let onSelect: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let positions = layout(in: geo.size)
            ZStack {
                // edges
                Path { p in
                    for e in edges {
                        guard let a = positions[e.src], let b = positions[e.dst] else { continue }
                        p.move(to: a); p.addLine(to: b)
                    }
                }
                .stroke(DS.Color.border, lineWidth: 1)

                // nodes
                ForEach(notes) { note in
                    if let pt = positions[note.id] {
                        nodeView(note)
                            .position(pt)
                            .onTapGesture { onSelect(note.id) }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(DS.Color.surfaceElevated.opacity(0.4)))
        }
    }

    private func nodeView(_ note: MemoryNote) -> some View {
        let color = nodeColor(note.kind)
        return VStack(spacing: 2) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(note.title)
                .font(DS.Typo.micro)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 90)
        }
    }

    /// Deterministic circular layout. Notes with more links sit toward the centre.
    private func layout(in size: CGSize) -> [String: CGPoint] {
        guard !notes.isEmpty else { return [:] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 50

        // degree per node (for inner/outer ring)
        var degree: [String: Int] = [:]
        for e in edges {
            degree[e.src, default: 0] += 1
            degree[e.dst, default: 0] += 1
        }

        var result: [String: CGPoint] = [:]
        let n = notes.count
        for (i, note) in notes.enumerated() {
            let angle = (Double(i) / Double(n)) * 2 * .pi - .pi / 2
            // hubs (degree >= 2) sit on an inner ring
            let r = (degree[note.id] ?? 0) >= 2 ? radius * 0.45 : radius
            result[note.id] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
        }
        // single node: centre it
        if n == 1, let only = notes.first { result[only.id] = center }
        return result
    }

    private func nodeColor(_ kind: MemoryNote.Kind) -> Color {
        switch kind {
        case .fact: return DS.Color.accent
        case .rule: return DS.Color.success
        case .playbook: return DS.Color.purple
        case .session: return DS.Color.textSecondary
        case .variable: return DS.Color.teal
        }
    }
}
