import SwiftUI

struct WorkflowDetailView: View {
    @EnvironmentObject var state: AppState
    let workflow: Workflow

    @State private var graph: WorkflowGraph = .empty
    @State private var didLoad: Bool = false
    @State private var isDirty: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showRunSheet: Bool = false
    @State private var saveStatus: String?
    @State private var mode: ViewMode = .visual

    enum ViewMode: String, CaseIterable, Identifiable {
        case visual = "Visual"
        case text = "Text"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            modePicker
            Divider()
            switch mode {
            case .visual:
                WorkflowGraphEditor(graph: $graph)
                    .environmentObject(state)
                    .onChange(of: graph) { _, _ in isDirty = true }
            case .text:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        triggersCard
                        stepsCard
                    }
                    .padding(20)
                }
            }
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: workflow.id) { _, _ in didLoad = false; loadIfNeeded() }
        .alert("Delete workflow '\(workflow.name)'?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { performDelete() }
        }
        .sheet(isPresented: $showRunSheet) {
            RunWorkflowSheet(workflow: workflow)
                .environmentObject(state)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.connected.to.line.below").font(.title)
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(workflow.name).font(.title2.bold())
                    if isDirty {
                        Text("unsaved").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                if !workflow.description.isEmpty {
                    Text(workflow.description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let s = saveStatus {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
            Button { showRunSheet = true } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(PressableButtonStyle(fill: DS.Color.success))
            .help("Запустить workflow через orchestrator-агента (живой запуск с токенами)")
            Button { save() } label: { Label("Save", systemImage: "checkmark.circle.fill") }
                .buttonStyle(PressableButtonStyle())
                .disabled(!isDirty)
                .help("Сохранить граф в файл .graph.json")
            Button {
                state.workflowsVM.editingWorkflow = workflow
            } label: { Label("Edit meta", systemImage: "pencil") }
                .buttonStyle(.bordered)
                .help("Изменить name / description / triggers (форма)")
            Button {
                showDeleteConfirm = true
            } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(.bordered).tint(.red)
                .help("Удалить workflow и его граф")
        }
        .padding(14)
    }

    private var modePicker: some View {
        HStack {
            Picker("", selection: $mode) {
                Label("Visual editor (BPMN-style)", systemImage: "rectangle.connected.to.line.below").tag(ViewMode.visual)
                Label("Text view", systemImage: "doc.plaintext").tag(ViewMode.text)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            Spacer()
            Text("\(graph.nodes.count) nodes • \(graph.edges.count) edges")
                .font(.caption).foregroundStyle(.secondary)
            Text("← drag блоки на холст; кнопка ⊞ Auto-layout сверху")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(DS.Color.surfaceElevated)
    }

    private var triggersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Triggers (\(workflow.triggers.count))").font(.headline)
            if workflow.triggers.isEmpty {
                Text("Нет триггеров — orchestrator не выберет workflow автоматически.")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(workflow.triggers, id: \.self) { trigger in
                        Text("\"\(trigger)\"")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps (rendered from graph)").font(.headline)
            if graph.nodes.isEmpty && workflow.steps.isEmpty {
                Text("(empty)").foregroundStyle(.secondary)
            } else {
                Text(graph.nodes.isEmpty ? workflow.steps : graph.toMarkdownSteps())
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .designCard()
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        graph = workflow.graph.nodes.isEmpty ? WorkflowGraph.newDefault() : workflow.graph
        isDirty = false
    }

    private func save() {
        do {
            _ = try state.container.workflowRepository.save(
                name: workflow.name,
                description: workflow.description,
                triggers: workflow.triggers,
                steps: workflow.steps,
                graph: graph,
                overwrite: true
            )
            isDirty = false
            saveStatus = "Saved"
            state.refresh()
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { saveStatus = nil }
            }
        } catch {
            saveStatus = "Failed: \(error.localizedDescription)"
        }
    }

    private func performDelete() {
        do {
            try state.container.workflowRepository.delete(workflow)
            state.refresh()
        } catch {
            saveStatus = "Delete failed: \(error.localizedDescription)"
        }
    }
}
