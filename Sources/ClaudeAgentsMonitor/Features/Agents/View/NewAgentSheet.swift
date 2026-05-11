import SwiftUI

struct NewAgentSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let editing: Agent?

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var model: String = "default"
    @State private var systemPrompt: String = ""
    @State private var selectedTools: Set<CommonTool> = []
    @State private var bashPatternsLegacy: String = ""
    @State private var bashAllowed: Set<String> = []
    @State private var newBashPattern: String = ""
    @State private var extraTools: String = ""
    @State private var allowAllMcp: Bool = false
    @State private var selectedMCPServers: Set<String> = []
    @State private var selectedSkills: Set<String> = []
    @State private var skillSearch: String = ""
    @State private var error: String?
    @State private var didLoad: Bool = false

    private let models = ["default", "haiku", "sonnet", "opus"]

    init(editing: Agent? = nil) {
        self.editing = editing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    sectionGroup(title: "Identity", icon: "person.crop.circle") {
                        nameRow
                        descriptionRow
                        modelRow
                    }
                    sectionGroup(title: "Permissions", icon: "key.fill") {
                        toolsRow
                        bashRow
                        extraToolsRow
                    }
                    sectionGroup(title: "Capabilities", icon: "puzzlepiece.extension.fill") {
                        skillsRow
                    }
                    sectionGroup(title: "Behavior", icon: "text.bubble.fill") {
                        promptRow
                    }
                }
                .padding(DS.Space.l)
            }
            .background(DS.Color.bg)
            Divider()
            footer
        }
        .frame(width: 800, height: 780)
        .onAppear { loadIfNeeded() }
        .sheet(isPresented: $state.projectsVM.showPluginsBrowserSheet) {
            PluginsBrowserSheet().environmentObject(state)
        }
    }

    @ViewBuilder
    private func sectionGroup<C: View>(title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(DS.Color.accent)
                Text(title).font(DS.Typo.headline)
            }
            content()
        }
        .designCard()
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(LinearGradient(
                        colors: [DS.Color.accent, DS.Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 36, height: 36)
                Image(systemName: editing == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(editing == nil ? "New agent" : "Edit agent")
                    .font(DS.Typo.title)
                if let editing {
                    Text(editing.name)
                        .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                } else {
                    Text("В проекте \(state.projectsVM.currentProject.name)")
                        .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SubtleTextButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(DS.Space.l)
        .background(DS.Color.surface)
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Name", "Lowercase, digits, hyphen — used as filename and slug")
            TextField("e.g. dev, git, review", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(editing != nil)
        }
    }

    private var descriptionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Description", "When to use this agent — Claude reads this when picking subagents")
            TextField("Short purpose (1-2 sentences)", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Model", "default = inherit from parent session")
            Picker("", selection: $model) {
                ForEach(models, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var toolsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Tools", "Pick what this agent can do (empty = inherit all)")
            FlowLayout(spacing: 8) {
                ForEach(CommonTool.allCases) { tool in
                    Toggle(isOn: Binding(
                        get: { selectedTools.contains(tool) },
                        set: { if $0 { selectedTools.insert(tool) } else { selectedTools.remove(tool) } }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.rawValue).font(.system(.caption, design: .monospaced))
                            Text(tool.description).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.button)
                }
            }
        }
    }

    private var bashRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("Bash access",
                         "Native Claude Code только whitelist. Чтобы запретить часть git — НЕ давай `git:*`, выбирай точные пресеты ниже.")

            // Active patterns chips
            if !bashAllowed.isEmpty {
                Text("Allowed (\(bashAllowed.count))")
                    .font(DS.Typo.captionMedium).foregroundStyle(DS.Color.textSecondary)
                FlowLayout(spacing: 4) {
                    ForEach(bashAllowed.sorted(), id: \.self) { pattern in
                        bashChip(pattern)
                    }
                }
            }

            // Custom add
            HStack(spacing: 6) {
                TextField("Custom pattern (e.g. git status:*)", text: $newBashPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typo.monoSmall)
                Button {
                    addCustomBash()
                } label: { Image(systemName: "plus") }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(newBashPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Quick presets — grouped
            Text("Quick presets")
                .font(DS.Typo.captionMedium).foregroundStyle(DS.Color.textSecondary)
                .padding(.top, DS.Space.s)
            ForEach(BashPresets.grouped(), id: \.category) { group in
                presetGroup(category: group.category, items: group.items)
            }
        }
    }

    private func presetGroup(category: String, items: [BashPreset]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category)
                .font(DS.Typo.micro).foregroundStyle(DS.Color.textTertiary).tracking(0.6)
            FlowLayout(spacing: 6) {
                ForEach(items) { preset in
                    presetButton(preset)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func presetButton(_ preset: BashPreset) -> some View {
        let allAdded = preset.patterns.allSatisfy { bashAllowed.contains($0) }
        let color: Color = {
            switch preset.dangerLevel {
            case .safe: return DS.Color.success
            case .moderate: return DS.Color.warning
            case .dangerous: return DS.Color.danger
            }
        }()
        return Button {
            if allAdded {
                preset.patterns.forEach { bashAllowed.remove($0) }
            } else {
                preset.patterns.forEach { bashAllowed.insert($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: allAdded ? "checkmark.circle.fill" : preset.icon)
                Text(preset.label).font(DS.Typo.captionMedium)
                Text("(\(preset.patterns.count))").font(DS.Typo.micro).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Space.s).padding(.vertical, 5)
            .foregroundStyle(allAdded ? color : DS.Color.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(allAdded ? color.opacity(0.12) : DS.Color.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .stroke(allAdded ? color.opacity(0.4) : DS.Color.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(preset.note.isEmpty
              ? preset.patterns.joined(separator: ", ")
              : "\(preset.note)\n\nPatterns:\n• " + preset.patterns.joined(separator: "\n• "))
    }

    private func bashChip(_ pattern: String) -> some View {
        Button {
            bashAllowed.remove(pattern)
        } label: {
            HStack(spacing: 4) {
                Text(pattern).font(DS.Typo.monoSmall)
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Space.s).padding(.vertical, 3)
            .background(
                Capsule().fill(DS.Color.accent.opacity(0.10))
                    .overlay(Capsule().stroke(DS.Color.accent.opacity(0.3), lineWidth: 1))
            )
            .foregroundStyle(DS.Color.accent)
        }
        .buttonStyle(.plain)
        .help("Click to remove `Bash(\(pattern))`")
    }

    private func addCustomBash() {
        let p = newBashPattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        bashAllowed.insert(p)
        newBashPattern = ""
    }

    private var extraToolsRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("MCP servers", "Подключенные MCP-серверы. Каждый агент должен явно получить доступ — по умолчанию ничего не наследуется.")
            if state.agentsVM.availableMCPServers.isEmpty {
                Text("Нет настроенных MCP серверов в ~/.claude.json. Подключи MCP в Claude Code сначала.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(DS.Space.s)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
            } else {
                FlowLayout(spacing: DS.Space.s) {
                    ForEach(state.agentsVM.availableMCPServers) { server in
                        mcpServerToggle(server)
                    }
                }
            }
            Toggle("Allow ALL MCP tools (mcp__*)", isOn: $allowAllMcp)
                .controlSize(.small)
                .help("Универсальный wildcard — агент получит доступ ко всем MCP-тулам всех серверов")

            sectionLabel("Other tools", "Дополнительные tool-выражения, через запятую. Для редких случаев.")
            TextField("(optional, comma-separated)", text: $extraTools)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func mcpServerToggle(_ server: MCPServer) -> some View {
        let isSelected = selectedMCPServers.contains(server.name)
        return Button {
            if isSelected { selectedMCPServers.remove(server.name) }
            else { selectedMCPServers.insert(server.name) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textTertiary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(server.name)
                        .font(DS.Typo.bodyMedium)
                    Text("mcp__\(server.name)__*")
                        .font(DS.Typo.monoSmall)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .padding(.horizontal, DS.Space.s).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(isSelected ? DS.Color.accent.opacity(0.10) : DS.Color.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .stroke(isSelected ? DS.Color.accent.opacity(0.4) : DS.Color.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("\(server.name) MCP server (scope: \(server.scope)). Включит mcp__\(server.name)__* в tools агента.")
    }

    private var skillsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("Skills", "Pick skills the agent can invoke via the Skill tool")
                Spacer()
                Text("\(selectedSkills.count) / \(state.agentsVM.availableSkills.count) selected")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
            }
            HStack(spacing: 8) {
                TextField("Filter…", text: $skillSearch)
                    .textFieldStyle(.roundedBorder)
                Button("All") { selectedSkills = Set(filteredSkills.map(\.id)) }
                    .controlSize(.small)
                Button("None") { selectedSkills.removeAll() }
                    .controlSize(.small)
                Button {
                    state.projectsVM.showPluginsBrowserSheet = true
                } label: {
                    Label("+ Browse plugins", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(GhostButtonStyle(tint: DS.Color.purple))
                .help("Открыть marketplace 177+ плагинов — каждый может добавить новые скиллы")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredSkills) { skill in
                        skillRow(skill)
                    }
                    if filteredSkills.isEmpty {
                        Text(state.agentsVM.availableSkills.isEmpty
                             ? "Скиллов нет — нажми ‘Browse plugins’ чтобы установить плагины с скиллами"
                             : "No skills match '\(skillSearch)'")
                            .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                            .padding(8)
                    }
                }
            }
            .frame(height: 200)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        let isSelected = selectedSkills.contains(skill.id)
        return Button {
            if isSelected { selectedSkills.remove(skill.id) }
            else { selectedSkills.insert(skill.id) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(skill.name).font(.system(.callout, design: .monospaced).bold())
                        Text(skill.source)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(badgeColor(for: skill.source).opacity(0.18))
                            .foregroundStyle(badgeColor(for: skill.source))
                            .clipShape(Capsule())
                    }
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func badgeColor(for source: String) -> Color {
        if source == "built-in" { return .purple }
        if source == "user" { return .green }
        return .blue
    }

    private var filteredSkills: [Skill] {
        let q = skillSearch.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return state.agentsVM.availableSkills }
        return state.agentsVM.availableSkills.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private var promptRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("System prompt", "How the agent thinks and behaves (skills block is auto-appended)")
            TextEditor(text: $systemPrompt)
                .font(.system(.callout, design: .monospaced))
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var footer: some View {
        HStack {
            if let err = error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Color.danger).font(DS.Typo.caption)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SubtleTextButtonStyle())
            Button(editing == nil ? "Create agent" : "Save changes") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PressableButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(DS.Space.l)
        .background(DS.Color.surface)
    }

    private func sectionLabel(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.callout.weight(.semibold))
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let agent = editing else { didLoad = true; return }
        didLoad = true
        name = agent.name
        description = agent.description
        model = agent.model ?? "default"
        systemPrompt = agent.promptWithoutInjectedBlocks

        // Parse tools back into form fields.
        var extras: [String] = []
        for raw in agent.tools {
            if raw == "Skill" { continue } // auto-added when skills selected
            if raw == "mcp__*" { allowAllMcp = true; continue }
            if raw.hasPrefix("mcp__") && raw.hasSuffix("__*") {
                let mid = raw.dropFirst(5).dropLast(3)
                selectedMCPServers.insert(String(mid))
                continue
            }
            if let known = CommonTool(rawValue: raw) {
                selectedTools.insert(known)
            } else if raw.hasPrefix("Bash(") && raw.hasSuffix(")") {
                bashAllowed.insert(String(raw.dropFirst(5).dropLast(1)))
            } else {
                extras.append(raw)
            }
        }
        extraTools = extras.joined(separator: ", ")

        // Pre-select previously attached skills (match by name).
        let attached = Set(agent.attachedSkills)
        selectedSkills = Set(state.agentsVM.availableSkills
            .filter { attached.contains($0.name) }
            .map(\.id))
    }

    private func collectTools() -> [String] {
        var tools: [String] = selectedTools.map(\.rawValue)
        for pattern in bashAllowed.sorted() {
            tools.append("Bash(\(pattern))")
        }
        for serverName in selectedMCPServers.sorted() {
            tools.append("mcp__\(serverName)__*")
        }
        let extras = extraTools
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        tools.append(contentsOf: extras)
        if allowAllMcp { tools.append("mcp__*") }
        return tools
    }

    private func save() {
        let chosenSkills = state.agentsVM.availableSkills.filter { selectedSkills.contains($0.id) }
        do {
            _ = try state.container.agentRepository.save(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description,
                model: model,
                tools: collectTools(),
                systemPrompt: systemPrompt,
                skills: chosenSkills,
                overwrite: editing != nil
            )
            state.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
