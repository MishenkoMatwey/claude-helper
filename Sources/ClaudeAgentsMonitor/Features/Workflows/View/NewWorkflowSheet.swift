import SwiftUI

struct NewWorkflowSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let editing: Workflow?

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var triggers: String = ""
    @State private var steps: String = defaultSteps
    @State private var error: String?
    @State private var didLoad: Bool = false

    init(editing: Workflow? = nil) {
        self.editing = editing
    }

    private static let defaultSteps = """
    ## Steps

    1. **<agent-name>** — что делает на этом шаге
       - Что передать в prompt
       - on_pass: переходи к шагу 2
       - on_fail: останови, покажи юзеру

    2. **<another-agent>** — следующий шаг
       - используй вывод предыдущего агента
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameRow
                    descriptionRow
                    triggersRow
                    stepsRow
                    helpRow
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 720)
        .onAppear { loadIfNeeded() }
    }

    private var header: some View {
        HStack {
            Image(systemName: editing == nil ? "rectangle.connected.to.line.below" : "pencil.tip.crop.circle")
                .foregroundStyle(.tint).font(.title)
            Text(editing == nil ? "New workflow" : "Edit workflow — \(editing!.name)")
                .font(.title2.bold())
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle()).keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Name", "Lowercase, digits, hyphen — used as filename")
            TextField("e.g. commit-flow, deploy-pipeline", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(editing != nil)
        }
    }

    private var descriptionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Description", "Что делает workflow — orchestrator читает")
            TextField("Короткое описание", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var triggersRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Triggers", "Фразы которые активируют workflow — через запятую")
            TextField(#"e.g. commit it, закоммить, ship it"#, text: $triggers)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var stepsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Steps", "Markdown с шагами — каждый шаг = вызов агента")
            TextEditor(text: $steps)
                .font(.system(.callout, design: .monospaced))
                .frame(height: 280)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var helpRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Доступные агенты:").font(.caption.weight(.semibold))
            FlowLayout(spacing: 4) {
                ForEach(state.agentsVM.agents.filter { $0.name != OrchestratorBuilder.agentName }) { a in
                    Text(a.name)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle())
            Button(editing == nil ? "Create workflow" : "Save changes") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PressableButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
    }

    private func sectionLabel(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.callout.weight(.semibold))
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let wf = editing else { didLoad = true; return }
        didLoad = true
        name = wf.name
        description = wf.description
        triggers = wf.triggers.joined(separator: ", ")
        steps = wf.steps
    }

    private func save() {
        let triggerList = triggers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            _ = try state.container.workflowRepository.save(
                name: trimmedName,
                description: description,
                triggers: triggerList,
                steps: steps,
                graph: .empty,
                overwrite: editing != nil
            )
            state.refresh()
            // Auto-select the new/edited workflow so user lands on the visual editor.
            state.workflowsVM.pendingSelectionWorkflowId = trimmedName
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
