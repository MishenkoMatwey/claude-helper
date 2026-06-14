import SwiftUI
import AppKit

struct AgentDetailView: View {
    @EnvironmentObject var state: AppState
    let agent: Agent
    @State private var showDeleteConfirm: Bool = false
    @State private var deleteError: String?
    @State private var trainCopied: Bool = false
    @State private var showIdentityEditor: Bool = false

    private func trainCommand() -> String {
        "claude --agent \(agent.name) --append-system-prompt 'TRAINING MODE: подробно документируй каждый шаг. После задачи ОБЯЗАТЕЛЬНО создай или обнови playbook в ~/.claude/agents/memory/\(agent.name).playbooks.md и покажи мне для подтверждения.'"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metaCard
                AgentPermissionsCard(agent: agent)
                if !agent.attachedSkills.isEmpty {
                    skillsCard
                }
                AgentVariablesCard(agentName: agent.name)
                AgentMemoryV3Card(agentName: agent.name)
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
        .sheet(isPresented: $showIdentityEditor) {
            AgentIdentityEditor(agent: agent).environmentObject(state)
        }
    }

    private var header: some View {
        let desc = AgentTemplate.iconDescriptor(for: agent)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    showIdentityEditor = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(desc.color.opacity(0.15))
                            .frame(width: 44, height: 44)
                        TemplateIcon(assetIcon: desc.asset, sfSymbol: desc.symbol,
                                     tint: desc.color, size: 26)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to change icon or rename")
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(agent.name).font(.title.bold())
                        Button {
                            showIdentityEditor = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Rename / change icon")
                    }
                    if !agent.description.isEmpty {
                        Text(agent.description).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button {
                        launchTrainingInTerminal()
                    } label: {
                        Label("Open in Terminal", systemImage: "terminal")
                    }
                    Button {
                        launchTrainingInITerm()
                    } label: {
                        Label("Open in iTerm", systemImage: "terminal.fill")
                    }
                    Divider()
                    Button {
                        copyTrainCommand()
                    } label: {
                        Label(trainCopied ? "Copied!" : "Copy command", systemImage: "doc.on.doc")
                    }
                } label: {
                    Label("Train…", systemImage: "graduationcap.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .tint(.blue)
                .help("Run agent in TRAINING MODE — agent documents every step into memory")
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

    private func launchTrainingInTerminal() {
        let projectPath = state.projectsVM.currentProject.path
        // Escape both for JSON-like AppleScript and for shell.
        let cmd = trainCommand()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let cd = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(cd)\\" && \(cmd)"
        end tell
        """
        runOsascript(script)
    }

    private func launchTrainingInITerm() {
        let projectPath = state.projectsVM.currentProject.path
        let cmd = trainCommand()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let cd = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm"
            activate
            create window with default profile
            tell current session of current window
                write text "cd \\"\(cd)\\" && \(cmd)"
            end tell
        end tell
        """
        runOsascript(script)
    }

    private func runOsascript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
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
