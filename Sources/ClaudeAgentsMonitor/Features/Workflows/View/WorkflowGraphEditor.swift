import SwiftUI
import AppKit

struct WorkflowGraphEditor: View {
    @EnvironmentObject var state: AppState
    @Binding var graph: WorkflowGraph

    @State private var selectedNodeId: String?
    @State private var selectedEdgeId: String?
    @State private var connectFromId: String?
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var canvasMousePos: CGPoint = .zero
    @State private var hoveredNodeId: String?
    @State private var dragConnectFrom: String?
    @State private var dragConnectPoint: CGPoint = .zero
    @State private var showIssues: Bool = true
    @State private var showMiniMap: Bool = true

    private let nodeSize = CGSize(width: 160, height: 60)

    private var issues: [ValidationIssue] {
        WorkflowValidator.validate(graph, agents: state.agentsVM.agents)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                canvas
                if showIssues && !issues.isEmpty {
                    Divider()
                    issuesPanel
                }
            }
            inspector
                .frame(minWidth: 280, idealWidth: 320)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Menu {
                let agents = state.agentsVM.agents.filter { $0.name != OrchestratorBuilder.agentName }
                Menu("Agent") {
                    if agents.isEmpty {
                        Text("Нет агентов. Создай в sidebar Dashboard.")
                    } else {
                        ForEach(agents) { a in
                            Button {
                                addNode(.agent, label: a.name, prompt: a.description)
                            } label: {
                                Label(a.name, systemImage: "person.crop.circle")
                            }
                        }
                    }
                }
                Button("Gateway (condition)") { addNode(.gateway, label: "passed") }
                Button("Parallel (fork)") { addNode(.parallel, label: "parallel") }
            } label: {
                Label("Add node", systemImage: "plus.square.fill")
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 130)

            Label("Hover node → drag from edge port", systemImage: "arrow.up.arrow.down")
                .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)

            Spacer()

            Button {
                graph = WorkflowLayout.autoLayout(graph)
                clearAllSelection()
                dragOffsets.removeAll()
            } label: {
                Label("Auto-layout", systemImage: "rectangle.3.group")
            }
            .controlSize(.small)
            .help("Automatically arrange nodes by tier")

            issueSummaryButton

            Button {
                if let nid = selectedNodeId { deleteNode(nid) }
                if let eid = selectedEdgeId { deleteEdge(eid) }
            } label: {
                Label("Delete selected", systemImage: "trash")
            }
            .disabled(deleteDisabledForSelection)
            .controlSize(.small)
        }
        .padding(8)
        .background(DS.Color.surfaceElevated)
    }

    private var issueSummaryButton: some View {
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        let total = issues.count
        return Button {
            showIssues.toggle()
        } label: {
            HStack(spacing: 4) {
                if errors > 0 {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text("\(errors)").font(.caption.bold())
                }
                if warnings > 0 {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(warnings)").font(.caption.bold())
                }
                if total == 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("valid").font(.caption)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(total == 0 ? "Workflow is valid" : "\(total) issues — click to toggle panel")
    }

    private var issuesPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Issues (\(issues.count))").font(.caption.weight(.semibold))
                Spacer()
                Button("Hide") { showIssues = false }
                    .controlSize(.mini)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(issues) { issue in
                        Button {
                            if let nid = issue.nodeId {
                                selectedNodeId = nid; selectedEdgeId = nil
                            } else if let eid = issue.edgeId {
                                selectedEdgeId = eid; selectedNodeId = nil
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: severityIcon(issue.severity))
                                    .foregroundStyle(severityColor(issue.severity))
                                Text(issue.message).font(.caption)
                                Spacer()
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(8)
        .background(DS.Color.surfaceElevated)
    }

    private func severityIcon(_ s: ValidationIssue.Severity) -> String {
        switch s {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func severityColor(_ s: ValidationIssue.Severity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                canvasContent
                if showMiniMap && graph.nodes.count > 1 {
                    minimap
                        .padding(DS.Space.s)
                }
            }
        }
    }

    private var minimap: some View {
        let allX = graph.nodes.map(\.x)
        let allY = graph.nodes.map(\.y)
        let minX = (allX.min() ?? 0) - 30
        let minY = (allY.min() ?? 0) - 30
        let maxX = (allX.max() ?? 1000) + 200
        let maxY = (allY.max() ?? 600) + 100
        let w = max(1, maxX - minX)
        let h = max(1, maxY - minY)
        let mapSize = CGSize(width: 140, height: 90)
        let scale = min(mapSize.width / w, mapSize.height / h)
        return ZStack {
            ForEach(graph.edges) { edge in
                if let from = graph.node(edge.from), let to = graph.node(edge.to) {
                    Path { p in
                        p.move(to: CGPoint(x: (from.x - minX) * scale, y: (from.y - minY) * scale))
                        p.addLine(to: CGPoint(x: (to.x - minX) * scale, y: (to.y - minY) * scale))
                    }
                    .stroke(DS.Color.textTertiary, lineWidth: 1)
                }
            }
            ForEach(graph.nodes) { node in
                Circle()
                    .fill(nodeColor(for: node.kind))
                    .frame(width: 6, height: 6)
                    .position(x: (node.x - minX) * scale, y: (node.y - minY) * scale)
            }
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .padding(DS.Space.xs)
        .background(DS.Color.surface.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.s).stroke(DS.Color.border))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .onTapGesture { showMiniMap = false }
        .help("Mini-map — клик чтобы скрыть")
    }

    private var canvasContent: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .textBackgroundColor)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearAllSelection()
                    }

                // Edges
                ForEach(graph.edges) { edge in
                    edgeView(edge)
                }

                // In-progress connect line (click-mode or drag-mode)
                if let fromId = dragConnectFrom ?? connectFromId,
                   let from = graph.node(fromId) {
                    let p1 = nodeCenter(from)
                    let p2 = (dragConnectFrom != nil) ? dragConnectPoint : canvasMousePos
                    Path { p in
                        p.move(to: p1)
                        let dx = p2.x - p1.x
                        let cp1 = CGPoint(x: p1.x + dx * 0.5, y: p1.y)
                        let cp2 = CGPoint(x: p2.x - dx * 0.5, y: p2.y)
                        p.addCurve(to: p2, control1: cp1, control2: cp2)
                    }
                    .stroke(DS.Color.accent.opacity(0.8),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
                    Circle().fill(DS.Color.accent).frame(width: 10, height: 10).position(p2)
                }

                // Node visuals — frame locked to body, no port expansion.
                ForEach(graph.nodes) { node in
                    let size = nodeSizeFor(node.kind)
                    nodeView(node)
                        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m))
                        .frame(width: size.width, height: size.height)
                        .onHover { hovering in
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                if hovering { hoveredNodeId = node.id }
                                else if hoveredNodeId == node.id { hoveredNodeId = nil }
                            }
                        }
                        .position(x: node.x, y: node.y)
                        .offset(dragOffsets[node.id] ?? .zero)
                        .gesture(dragGesture(for: node))
                        .onTapGesture { tapNode(node) }
                }
                // Drop-target highlight (rendered above nodes)
                ForEach(graph.nodes) { node in
                    if isDropTarget(node) {
                        dropTargetOverlay(for: node)
                            .position(currentPosition(for: node))
                            .allowsHitTesting(false)
                    }
                }
                // Ports — rendered in their own layer above nodes, no frame lock,
                // so hit-test works for ports near the edges of any block (incl. Start/End).
                ForEach(graph.nodes) { node in
                    if shouldShowPorts(for: node) {
                        connectionPorts(for: node)
                            .position(currentPosition(for: node))
                            .onHover { hovering in
                                if hovering { hoveredNodeId = node.id }
                            }
                    }
                }
            }
            .background(
                MouseTrackingView { pos in canvasMousePos = pos }
            )
            .coordinateSpace(name: "workflowCanvas")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func edgeView(_ edge: WorkflowEdge) -> some View {
        let from = graph.node(edge.from)
        let to = graph.node(edge.to)
        let points = connectionPoints(from: from, to: to)
        let p1 = points.start
        let p2 = points.end
        let isSelected = selectedEdgeId == edge.id
        let edgeColor: Color = isSelected ? DS.Color.accent
            : (edge.condition.lowercased().contains("fail") ? DS.Color.danger.opacity(0.75)
               : edge.condition.lowercased().contains("pass") ? DS.Color.success.opacity(0.75)
               : DS.Color.textSecondary.opacity(0.65))
        // Stop the line short of arrow head so the head is distinct.
        let arrowHeadSize: CGFloat = isSelected ? 16 : 14
        let lineEnd = pointAlongLine(from: p1, to: p2, shortenedBy: arrowHeadSize * 0.85)
        let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        return ZStack {
            Path { p in
                p.move(to: p1)
                let dx = lineEnd.x - p1.x
                let cp1 = CGPoint(x: p1.x + dx * 0.5, y: p1.y)
                let cp2 = CGPoint(x: lineEnd.x - dx * 0.5, y: lineEnd.y)
                p.addCurve(to: lineEnd, control1: cp1, control2: cp2)
            }
            .stroke(edgeColor, style: StrokeStyle(lineWidth: isSelected ? 2.5 : 2, lineCap: .round))
            .contentShape(EdgeHitShape(p1: p1, p2: lineEnd))
            .onTapGesture {
                selectedEdgeId = edge.id
                selectedNodeId = nil
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

            ArrowHead(at: p2, from: p1, size: arrowHeadSize)
                .fill(edgeColor)

            if !edge.condition.isEmpty {
                Text(edge.condition)
                    .font(DS.Typo.micro)
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, 2)
                    .foregroundStyle(edgeColor)
                    .background(
                        Capsule().fill(.thinMaterial)
                    )
                    .position(mid)
                    .onTapGesture { selectedEdgeId = edge.id; selectedNodeId = nil }
            }
        }
    }

    private func pointAlongLine(from a: CGPoint, to b: CGPoint, shortenedBy distance: CGFloat) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > distance else { return b }
        let scale = (len - distance) / len
        return CGPoint(x: a.x + dx * scale, y: a.y + dy * scale)
    }

    private func nodeView(_ node: WorkflowNode) -> some View {
        let isSelected = selectedNodeId == node.id
        let strokeColor: Color = isSelected ? DS.Color.accent : nodeColor(for: node.kind).opacity(0.4)
        let strokeWidth: CGFloat = isSelected ? 2.5 : 1
        return Group {
            switch node.kind {
            case .start:
                Capsule()
                    .fill(LinearGradient(colors: [DS.Color.success.opacity(0.20), DS.Color.success.opacity(0.10)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(strokeColor, lineWidth: strokeWidth))
                    .frame(width: 100, height: 38)
                    .overlay(
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").imageScale(.small)
                            Text(node.label)
                        }
                        .font(DS.Typo.bodyMedium)
                        .foregroundStyle(DS.Color.success)
                    )
                    .shadow(color: isSelected ? DS.Color.accent.opacity(0.3) : .black.opacity(0.15), radius: isSelected ? 8 : 4, y: 2)
            case .end:
                Capsule()
                    .fill(LinearGradient(colors: [DS.Color.danger.opacity(0.20), DS.Color.danger.opacity(0.10)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(strokeColor, lineWidth: strokeWidth))
                    .frame(width: 100, height: 38)
                    .overlay(
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill").imageScale(.small)
                            Text(node.label)
                        }
                        .font(DS.Typo.bodyMedium)
                        .foregroundStyle(DS.Color.danger)
                    )
                    .shadow(color: isSelected ? DS.Color.accent.opacity(0.3) : .black.opacity(0.15), radius: isSelected ? 8 : 4, y: 2)
            case .agent:
                RoundedRectangle(cornerRadius: DS.Radius.m)
                    .fill(LinearGradient(colors: [DS.Color.surfaceElevated, DS.Color.surface],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(strokeColor, lineWidth: strokeWidth))
                    .frame(width: nodeSize.width, height: nodeSize.height)
                    .overlay(
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(DS.Color.accent.opacity(0.18))
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "person.crop.circle.fill")
                                        .imageScale(.small)
                                        .foregroundStyle(DS.Color.accent)
                                }
                                Text(node.label)
                                    .font(DS.Typo.bodyMedium)
                                    .lineLimit(1)
                                Spacer()
                            }
                            if !node.prompt.isEmpty {
                                Text(node.prompt)
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(DS.Space.s)
                    )
                    .shadow(color: isSelected ? DS.Color.accent.opacity(0.3) : .black.opacity(0.15), radius: isSelected ? 10 : 5, y: 3)
            case .gateway:
                Diamond()
                    .fill(LinearGradient(colors: [DS.Color.warning.opacity(0.30), DS.Color.warning.opacity(0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Diamond().stroke(strokeColor, lineWidth: strokeWidth))
                    .frame(width: 110, height: 110)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "questionmark.diamond.fill")
                                .foregroundStyle(DS.Color.warning)
                            Text(node.label).font(DS.Typo.captionMedium).lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(DS.Space.s)
                    )
                    .shadow(color: isSelected ? DS.Color.accent.opacity(0.3) : .black.opacity(0.15), radius: isSelected ? 10 : 5, y: 3)
            case .parallel:
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(LinearGradient(colors: [DS.Color.purple.opacity(0.30), DS.Color.purple.opacity(0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.s).stroke(strokeColor, lineWidth: strokeWidth))
                    .frame(width: 28, height: 80)
                    .overlay(
                        Image(systemName: "rectangle.split.3x1.fill")
                            .foregroundStyle(DS.Color.purple)
                    )
                    .shadow(color: isSelected ? DS.Color.accent.opacity(0.3) : .black.opacity(0.15), radius: isSelected ? 8 : 4, y: 2)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private func shouldShowPorts(for node: WorkflowNode) -> Bool {
        hoveredNodeId == node.id
            || selectedNodeId == node.id
            || connectFromId == node.id
            || dragConnectFrom == node.id
    }

    private func isDropTarget(_ node: WorkflowNode) -> Bool {
        guard let from = dragConnectFrom, from != node.id else { return false }
        let size = nodeSizeFor(node.kind)
        let center = currentPosition(for: node)
        let rect = CGRect(
            x: center.x - size.width / 2 - 6,
            y: center.y - size.height / 2 - 6,
            width: size.width + 12,
            height: size.height + 12
        )
        return rect.contains(dragConnectPoint)
    }

    @ViewBuilder
    private func dropTargetOverlay(for node: WorkflowNode) -> some View {
        let size = nodeSizeFor(node.kind)
        RoundedRectangle(cornerRadius: DS.Radius.m)
            .stroke(DS.Color.success, style: StrokeStyle(lineWidth: 3, dash: [4, 3]))
            .frame(width: size.width + 8, height: size.height + 8)
            .shadow(color: DS.Color.success.opacity(0.5), radius: 8)
    }

    private func connectionPorts(for node: WorkflowNode) -> some View {
        let size = nodeSizeFor(node.kind)
        return ZStack {
            ForEach(allowedPortSides(for: node.kind), id: \.self) { side in
                portCircle(node: node, side: side, size: size)
            }
        }
        .transition(.opacity)
    }

    /// Start exits only on the right (side 1). End enters only on the left (side 3).
    /// Other nodes show all 4 ports.
    private func allowedPortSides(for kind: WorkflowNodeKind) -> [Int] {
        switch kind {
        case .start: return [1]
        case .end: return [3]
        default: return [0, 1, 2, 3]
        }
    }

    private func portCircle(node: WorkflowNode, side: Int, size: CGSize) -> some View {
        // Bigger transparent hit-area with smaller visible dot inside.
        Color.clear
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .fill(DS.Color.accent)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: DS.Color.accent.opacity(0.5), radius: 4)
            )
            .contentShape(Rectangle())
            .offset(portOffset(side: side, size: size))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("workflowCanvas"))
                    .onChanged { v in
                        dragConnectFrom = node.id
                        dragConnectPoint = v.location
                    }
                    .onEnded { v in
                        defer { dragConnectFrom = nil }
                        guard let target = nodeAt(v.location, exclude: node.id) else { return }
                        let edge = WorkflowEdge(
                            id: UUID().uuidString,
                            from: node.id, to: target.id,
                            condition: "always"
                        )
                        graph.edges.append(edge)
                        selectedEdgeId = edge.id
                        selectedNodeId = nil
                    }
            )
            .help("Drag to another node to connect")
    }

    /// Endpoints at midpoint of the side facing the other node.
    /// Stable BPMN-style — arrow exits the right side, enters the left side, etc.
    private func connectionPoints(from: WorkflowNode?, to: WorkflowNode?) -> (start: CGPoint, end: CGPoint) {
        guard let from = from, let to = to else { return (.zero, .zero) }
        let c1 = currentPosition(for: from)
        let c2 = currentPosition(for: to)
        return (
            sideMidpoint(of: from, center: c1, towards: c2),
            sideMidpoint(of: to, center: c2, towards: c1)
        )
    }

    private func sideMidpoint(of node: WorkflowNode, center: CGPoint, towards: CGPoint) -> CGPoint {
        let size = nodeSizeFor(node.kind)
        let dx = towards.x - center.x
        let dy = towards.y - center.y
        if abs(dx) >= abs(dy) {
            // Exit/enter on right or left side
            return dx >= 0
                ? CGPoint(x: center.x + size.width / 2, y: center.y)
                : CGPoint(x: center.x - size.width / 2, y: center.y)
        } else {
            return dy >= 0
                ? CGPoint(x: center.x, y: center.y + size.height / 2)
                : CGPoint(x: center.x, y: center.y - size.height / 2)
        }
    }

    private func clearAllSelection() {
        selectedNodeId = nil
        selectedEdgeId = nil
        connectFromId = nil
        hoveredNodeId = nil
        // Also drop keyboard focus from any text field in the inspector.
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func nodeAt(_ point: CGPoint, exclude: String? = nil) -> WorkflowNode? {
        for node in graph.nodes {
            if node.id == exclude { continue }
            let size = nodeSizeFor(node.kind)
            let center = currentPosition(for: node)
            let rect = CGRect(
                x: center.x - size.width / 2 - 4,
                y: center.y - size.height / 2 - 4,
                width: size.width + 8,
                height: size.height + 8
            )
            if rect.contains(point) { return node }
        }
        return nil
    }

    private func portOffset(side: Int, size: CGSize) -> CGSize {
        switch side {
        case 0: return CGSize(width: 0, height: -size.height / 2)
        case 1: return CGSize(width: size.width / 2, height: 0)
        case 2: return CGSize(width: 0, height: size.height / 2)
        default: return CGSize(width: -size.width / 2, height: 0)
        }
    }

    private func nodeSizeFor(_ kind: WorkflowNodeKind) -> CGSize {
        switch kind {
        case .agent: return nodeSize
        case .gateway: return CGSize(width: 110, height: 110)
        case .parallel: return CGSize(width: 28, height: 80)
        case .start, .end: return CGSize(width: 100, height: 38)
        }
    }

    private func nodeColor(for kind: WorkflowNodeKind) -> Color {
        switch kind {
        case .start: return DS.Color.success
        case .end: return DS.Color.danger
        case .agent: return DS.Color.accent
        case .gateway: return DS.Color.warning
        case .parallel: return DS.Color.purple
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let nid = selectedNodeId, let idx = graph.nodes.firstIndex(where: { $0.id == nid }) {
                    nodeInspector(index: idx)
                } else if let eid = selectedEdgeId, let idx = graph.edges.firstIndex(where: { $0.id == eid }) {
                    edgeInspector(index: idx)
                } else {
                    helpInspector
                }
            }
            .padding(14)
        }
        .background(DS.Color.surfaceElevated)
    }

    private func nodeInspector(index: Int) -> some View {
        let node = graph.nodes[index]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: nodeIcon(node.kind))
                Text("\(node.kind.rawValue.capitalized) node").font(.headline)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(labelTitle(for: node.kind)).font(.caption.weight(.semibold))
                if node.kind == .agent {
                    Picker("", selection: Binding(
                        get: { graph.nodes[index].label },
                        set: { graph.nodes[index].label = $0 }
                    )) {
                        ForEach(state.agentsVM.agents.filter { $0.name != OrchestratorBuilder.agentName }) { a in
                            Text(a.name).tag(a.name)
                        }
                        if !state.agentsVM.agents.contains(where: { $0.name == graph.nodes[index].label }) {
                            Text(graph.nodes[index].label).tag(graph.nodes[index].label)
                        }
                    }
                    .labelsHidden()
                } else {
                    TextField("", text: Binding(
                        get: { graph.nodes[index].label },
                        set: { graph.nodes[index].label = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            if node.kind == .agent {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task / prompt").font(.caption.weight(.semibold))
                    TextEditor(text: Binding(
                        get: { graph.nodes[index].prompt },
                        set: { graph.nodes[index].prompt = $0 }
                    ))
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
            }
            if node.kind == .agent || node.kind == .parallel {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Priority (\(graph.nodes[index].priority))").font(.caption.weight(.semibold))
                    Slider(value: Binding(
                        get: { Double(graph.nodes[index].priority) },
                        set: { graph.nodes[index].priority = Int($0) }
                    ), in: 0...10, step: 1)
                }
            }
            // Outgoing branches — what happens after this node
            outgoingBranches(for: node)

            if node.kind != .start && node.kind != .end {
                HStack {
                    Spacer()
                    Button(role: .destructive) { deleteNode(node.id) } label: {
                        Label("Delete node", systemImage: "trash")
                    }
                }
            } else {
                Text("Start/End — обязательные блоки workflow, удалить нельзя.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    private func outgoingBranches(for node: WorkflowNode) -> some View {
        let outgoing = graph.edges.enumerated().filter { $0.element.from == node.id }
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("Branches — что делать после").font(.caption.weight(.semibold))
                Spacer()
                Text("\(outgoing.count)").font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            if node.kind == .agent {
                Text("Условия пишутся как `on pass`/`on fail` или своя строка — orchestrator интерпретирует вывод агента и матчит подходящую ветку.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            } else if node.kind == .gateway {
                Text("Gateway оценивает условие и идёт по совпавшей ветке.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            if outgoing.isEmpty {
                Text("Нет исходящих веток — добавь через кнопки ниже или 'Connect from selected' в toolbar.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(outgoing, id: \.element.id) { (idx, edge) in
                    branchRow(edgeIndex: idx, edge: edge)
                }
            }
            // Quick add buttons specific to agent nodes
            if node.kind == .agent {
                Text("Quick add").font(DS.Typo.micro).foregroundStyle(DS.Color.textTertiary).tracking(0.5)
                HStack(spacing: 4) {
                    quickConditionButton("on pass", color: DS.Color.success)
                    quickConditionButton("on fail", color: DS.Color.danger)
                    quickConditionButton("always", color: DS.Color.textSecondary)
                }
            }
            Button {
                connectFromId = node.id
            } label: {
                Label("Connect to other node…", systemImage: "arrow.right.circle.fill")
                    .font(DS.Typo.captionMedium)
            }
            .buttonStyle(GhostButtonStyle())
            .help("Click here, then click the target node — стрелка появится с условием 'always'")
        }
        .padding(DS.Space.s)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
    }

    private func branchRow(edgeIndex: Int, edge: WorkflowEdge) -> some View {
        let target = graph.node(edge.to)
        let color: Color = edge.condition.lowercased().contains("fail") ? DS.Color.danger
            : edge.condition.lowercased().contains("pass") ? DS.Color.success
            : DS.Color.textSecondary
        return HStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .foregroundStyle(color)
                .font(.system(size: 10, weight: .bold))
            TextField("condition", text: Binding(
                get: { graph.edges[edgeIndex].condition },
                set: { graph.edges[edgeIndex].condition = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(DS.Typo.monoSmall)
            .frame(width: 110)
            Text("→").foregroundStyle(DS.Color.textTertiary)
            Text(target?.label ?? "?")
                .font(DS.Typo.bodyMedium)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                deleteEdge(edge.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DS.Color.textTertiary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Delete this branch")
        }
        .padding(.vertical, 2)
    }

    private func quickConditionButton(_ condition: String, color: Color) -> some View {
        Button {
            // If selected node has connect outgoing without target — shouldn't happen.
            // Add a placeholder edge to End if exists, otherwise enter connect mode.
            if let nodeId = selectedNodeId {
                if let endNode = graph.nodes.first(where: { $0.kind == .end }) {
                    let edge = WorkflowEdge(
                        id: UUID().uuidString,
                        from: nodeId, to: endNode.id, condition: condition
                    )
                    graph.edges.append(edge)
                    selectedEdgeId = edge.id
                } else {
                    connectFromId = nodeId
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "plus.circle.fill").imageScale(.small)
                Text(condition).font(DS.Typo.captionMedium)
            }
            .padding(.horizontal, DS.Space.s).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(
                Capsule().fill(color.opacity(0.10))
                    .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .help("Add edge from this node to End with condition '\(condition)'")
    }

    private func edgeInspector(index: Int) -> some View {
        let edge = graph.edges[index]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.right.circle.fill")
                Text("Edge").font(.headline)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Condition / label").font(.caption.weight(.semibold))
                TextField(#"e.g. on pass, on fail, always, regex"#, text: Binding(
                    get: { graph.edges[index].condition },
                    set: { graph.edges[index].condition = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 4) {
                ForEach(["always", "on pass", "on fail", "if changed"], id: \.self) { preset in
                    Button(preset) { graph.edges[index].condition = preset }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
            HStack {
                let from = graph.node(edge.from)?.label ?? "?"
                let to = graph.node(edge.to)?.label ?? "?"
                Text("\(from) → \(to)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(role: .destructive) { deleteEdge(edge.id) } label: {
                    Label("Delete edge", systemImage: "trash")
                }
            }
        }
    }

    private var helpInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workflow editor").font(.headline)
            Text("• Add node — кнопка слева сверху\n• Drag блока — перемещение\n• Click — выбрать; повторно по холсту — снять\n• Connect — выбери блок, жми Connect, потом кликни целевой блок\n• Edge label — клик на стрелку, набери условие справа")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Палитра").font(.caption.weight(.semibold))
            paletteRow("Start", color: .green, icon: "play.circle.fill")
            paletteRow("Agent", color: .blue, icon: "person.crop.circle.fill")
            paletteRow("Gateway", color: .orange, icon: "questionmark.diamond.fill")
            paletteRow("Parallel", color: .purple, icon: "rectangle.split.3x1.fill")
            paletteRow("End", color: .red, icon: "stop.circle.fill")
        }
    }

    private func paletteRow(_ name: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(name).font(.caption)
        }
    }

    // MARK: - Helpers

    private func nodeIcon(_ k: WorkflowNodeKind) -> String {
        switch k {
        case .start: return "play.circle.fill"
        case .end: return "stop.circle.fill"
        case .agent: return "person.crop.circle.fill"
        case .gateway: return "questionmark.diamond.fill"
        case .parallel: return "rectangle.split.3x1.fill"
        }
    }

    private func labelTitle(for kind: WorkflowNodeKind) -> String {
        switch kind {
        case .agent: return "Agent name"
        case .gateway: return "Condition expression"
        case .parallel: return "Label"
        case .start: return "Label"
        case .end: return "Label"
        }
    }

    private func defaultAgentLabel() -> String {
        state.agentsVM.agents.first { $0.name != OrchestratorBuilder.agentName }?.name ?? "agent"
    }

    private func currentPosition(for node: WorkflowNode) -> CGPoint {
        let offset = dragOffsets[node.id] ?? .zero
        return CGPoint(x: node.x + offset.width, y: node.y + offset.height)
    }

    private func nodeCenter(_ node: WorkflowNode) -> CGPoint {
        currentPosition(for: node)
    }

    private func dragGesture(for node: WorkflowNode) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffsets[node.id] = value.translation
            }
            .onEnded { value in
                if let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) {
                    graph.nodes[idx].x += value.translation.width
                    graph.nodes[idx].y += value.translation.height
                }
                dragOffsets[node.id] = .zero
            }
    }

    private func tapNode(_ node: WorkflowNode) {
        if let from = connectFromId, from != node.id {
            let edge = WorkflowEdge(
                id: UUID().uuidString,
                from: from, to: node.id,
                condition: "always"
            )
            graph.edges.append(edge)
            connectFromId = nil
            selectedEdgeId = edge.id
            selectedNodeId = nil
        } else {
            selectedNodeId = node.id
            selectedEdgeId = nil
            connectFromId = nil
        }
    }

    private func addNode(_ kind: WorkflowNodeKind, label: String, prompt: String = "") {
        let id = "\(kind.rawValue)-\(Int.random(in: 1000...9999))"
        let node = WorkflowNode(
            id: id, kind: kind,
            x: 200 + Double.random(in: -40...40),
            y: 200 + Double.random(in: -40...40),
            label: label, prompt: prompt, priority: 0
        )
        graph.nodes.append(node)
        selectedNodeId = id
    }

    private var deleteDisabledForSelection: Bool {
        if let nid = selectedNodeId, let node = graph.node(nid) {
            if node.kind == .start || node.kind == .end { return true }
            return false
        }
        if selectedEdgeId != nil { return false }
        return true
    }

    private func deleteNode(_ id: String) {
        guard let node = graph.node(id) else { return }
        if node.kind == .start || node.kind == .end { return } // protected
        graph.nodes.removeAll { $0.id == id }
        graph.edges.removeAll { $0.from == id || $0.to == id }
        if selectedNodeId == id { selectedNodeId = nil }
    }

    private func deleteEdge(_ id: String) {
        graph.edges.removeAll { $0.id == id }
        if selectedEdgeId == id { selectedEdgeId = nil }
    }
}

// MARK: - Helpers

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// Hit-test shape for an edge — thick stroked bezier so only the line area is tappable.
struct EdgeHitShape: Shape {
    let p1: CGPoint
    let p2: CGPoint
    var lineWidth: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let path = Path { p in
            p.move(to: p1)
            let dx = p2.x - p1.x
            let cp1 = CGPoint(x: p1.x + dx * 0.5, y: p1.y)
            let cp2 = CGPoint(x: p2.x - dx * 0.5, y: p2.y)
            p.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

struct ArrowHead: Shape {
    let at: CGPoint
    let from: CGPoint
    var size: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let angle = atan2(at.y - from.y, at.x - from.x)
        let p1 = at
        let p2 = CGPoint(
            x: at.x - size * cos(angle - .pi / 6),
            y: at.y - size * sin(angle - .pi / 6)
        )
        let p3 = CGPoint(
            x: at.x - size * cos(angle + .pi / 6),
            y: at.y - size * sin(angle + .pi / 6)
        )
        var p = Path()
        p.move(to: p1)
        p.addLine(to: p2)
        p.addLine(to: p3)
        p.closeSubpath()
        return p
    }
}

struct MouseTrackingView: NSViewRepresentable {
    let onMove: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.onMove = onMove
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackingView)?.onMove = onMove
    }
}

private final class TrackingView: NSView {
    var onMove: ((CGPoint) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        // Flip Y: AppKit origin bottom-left, SwiftUI top-left.
        onMove?(CGPoint(x: loc.x, y: bounds.height - loc.y))
    }
}
