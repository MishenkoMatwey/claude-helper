import SwiftUI
import AppKit

struct AgentDetailView: View {
    @EnvironmentObject var state: AppState
    let agent: Agent
    @State private var showDeleteConfirm: Bool = false
    @State private var deleteError: String?
    @State private var showExtractSheet: Bool = false
    @State private var showMineSheet: Bool = false
    @State private var trainCopied: Bool = false

    private func privateMemoryURL(for agent: Agent) -> URL {
        state.container.agentRepository.agentsDirectory()
            .appendingPathComponent("memory/\(agent.name).md")
    }

    private func playbooksURL(for agent: Agent) -> URL {
        state.container.agentRepository.agentsDirectory()
            .appendingPathComponent("memory/\(agent.name).playbooks.md")
    }

    private func sharedMemoryURL() -> URL {
        state.container.agentRepository.agentsDirectory()
            .appendingPathComponent("SHARED.md")
    }

    private func trainCommand() -> String {
        "claude --agent \(agent.name) --append-system-prompt 'TRAINING MODE: подробно документируй каждый шаг. После задачи ОБЯЗАТЕЛЬНО создай или обнови playbook в ~/.claude/agents/memory/\(agent.name).playbooks.md и покажи мне для подтверждения.'"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metaCard
                AgentPermissionsCard(agent: agent)
                permissionsCard
                if !agent.attachedSkills.isEmpty {
                    skillsCard
                }
                AgentVariablesCard(agentName: agent.name)
                MemoryEditorView(
                    title: "Playbooks",
                    path: playbooksURL(for: agent),
                    placeholder: "# \(agent.name) — playbooks\n\n_Структурированные процедуры. Заполнятся автоматически или через Extract._\n"
                )
                MemoryEditorView(
                    title: "Private memory (журнал)",
                    path: privateMemoryURL(for: agent),
                    placeholder: "# \(agent.name) — private memory\n\n_Записи появятся здесь по мере работы агента._\n"
                )
                MemoryEditorView(
                    title: "Shared memory (все агенты)",
                    path: sharedMemoryURL(),
                    placeholder: "# Shared agent memory\n"
                )
                promptCard
            }
            .padding(20)
        }
        .alert("Delete agent '\(agent.name)'?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { performDelete() }
        } message: {
            Text("This removes ~/.claude/agents/\(agent.name).md. The private memory file is kept.")
        }
        .sheet(item: $state.agentsVM.editingAgent) { editing in
            NewAgentSheet(editing: editing).environmentObject(state)
        }
        .sheet(isPresented: $showExtractSheet) {
            ExtractPlaybookSheet(agent: agent)
                .environmentObject(state)
        }
        .sheet(isPresented: $showMineSheet) {
            MinePlaybooksSheet(agent: agent)
                .environmentObject(state)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "person.crop.circle.fill").font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(agent.name).font(.title.bold())
                    if !agent.description.isEmpty {
                        Text(agent.description).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    copyTrainCommand()
                } label: {
                    Label(trainCopied ? "Copied!" : "Train…", systemImage: "graduationcap.fill")
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .help("Copy CLI command for training mode session")
                Button {
                    showMineSheet = true
                } label: {
                    Label("Mine", systemImage: "rectangle.stack.badge.plus")
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
                .help("Auto-scan recent sessions and collect all playbooks found")
                Button {
                    showExtractSheet = true
                } label: {
                    Label("Extract", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                .help("Pick a single session and extract one playbook")
                Button {
                    state.agentsVM.editingAgent = agent
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .help("Edit agent settings — name (locked), description, tools, prompt")
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Delete the agent file. Private memory is kept on disk.")
            }
            if let err = deleteError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
        }
    }

    private func copyTrainCommand() {
        let cmd = trainCommand()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cmd, forType: .string)
        trainCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { trainCopied = false }
        }
    }

    private var skillsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attached skills (\(agent.attachedSkills.count))").font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(agent.attachedSkills, id: \.self) { skillName in
                    Text(skillName)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func performDelete() {
        do {
            try state.container.agentRepository.delete(agent)
            state.refresh()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private var metaCard: some View {
        HStack(spacing: 16) {
            chip("Model", agent.model ?? "default")
            chip("File", agent.filePath.lastPathComponent)
            chip("Memory", agent.memoryPath != nil ? "yes" : "—")
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions / tools").font(.headline)
            if agent.tools.isEmpty {
                Text("Inherits all parent tools").foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(agent.tools, id: \.self) { tool in
                        Text(tool)
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

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System prompt").font(.headline)
            ScrollView {
                Text(agent.systemPrompt.isEmpty ? "(empty)" : agent.systemPrompt)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 240)
        }
        .designCard()
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced))
        }
        .padding(10)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
