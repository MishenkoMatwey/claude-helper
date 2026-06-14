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
    @State private var iconAsset: String? = nil
    @State private var iconSymbol: String = ""
    @State private var iconColor: String = "blue"
    private let brandAssets = ["clussters", "git", "jira", "confluence", "figma", "database", "github", "gitlab", "chrome", "vscode", "intellij"]
    private let sfSymbols = [
        "person.crop.circle", "bolt.fill", "checklist", "cylinder.split.1x2.fill",
        "doc.richtext", "arrow.triangle.branch", "paintbrush.pointed.fill",
        "network", "shield.fill", "magnifyingglass", "wand.and.stars",
        "gearshape.fill", "terminal.fill", "globe", "lock.fill"
    ]
    private let colorChoices = ["blue", "orange", "purple", "green", "red", "gray"]

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
                        iconRow
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
                    Text("In project \(state.projectsVM.currentProject.name)")
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
            if let e = editing, e.name != name && !name.isEmpty {
                Label("Rename will move <name>.md + memory/<name>.* files and re-key Keychain entries from '\(e.name)' to '\(name)'.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var iconRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Icon", "Brand asset (recommended) or SF Symbol fallback")
            iconPreview
            HStack(spacing: 6) {
                ForEach(brandAssets, id: \.self) { a in
                    iconChoice(asset: a, sym: nil, selected: iconAsset == a)
                        .onTapGesture { iconAsset = a; iconSymbol = "" }
                }
                iconChoice(asset: nil, sym: nil, selected: iconAsset == nil && iconSymbol.isEmpty)
                    .onTapGesture { iconAsset = nil; iconSymbol = "" }
            }
            FlowLayout(spacing: 6) {
                ForEach(sfSymbols, id: \.self) { s in
                    iconChoice(asset: nil, sym: s,
                               selected: iconAsset == nil && iconSymbol == s)
                        .onTapGesture { iconAsset = nil; iconSymbol = s }
                }
            }
            HStack(spacing: 6) {
                Text("Custom SF symbol:").font(.caption).foregroundStyle(.secondary)
                TextField("any.sf.symbol.name", text: $iconSymbol)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .onChange(of: iconSymbol) { _, _ in if !iconSymbol.isEmpty { iconAsset = nil } }
            }
            HStack(spacing: 8) {
                Text("Color:").font(.caption).foregroundStyle(.secondary)
                ForEach(colorChoices, id: \.self) { c in
                    let tint = AgentTemplate.swiftUIColor(c)
                    Circle().fill(tint).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(iconColor == c ? Color.primary : .clear, lineWidth: 2))
                        .overlay(Image(systemName: iconColor == c ? "checkmark" : "")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 9, weight: .bold)))
                        .onTapGesture { iconColor = c }
                }
            }
        }
    }

    private var iconPreview: some View {
        let tint = AgentTemplate.swiftUIColor(iconColor)
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.15))
                    .frame(width: 42, height: 42)
                TemplateIcon(assetIcon: iconAsset,
                             sfSymbol: iconSymbol.isEmpty ? "person.crop.circle" : iconSymbol,
                             tint: tint, size: 24)
            }
            Text("Preview").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func iconChoice(asset: String?, sym: String?, selected: Bool) -> some View {
        let tint = AgentTemplate.swiftUIColor(iconColor)
        let label: String = {
            if let a = asset { return a }
            if let s = sym, !s.isEmpty { return s }
            return "none"
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? tint.opacity(0.22) : Color.secondary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(selected ? tint : Color.secondary.opacity(0.3),
                                    lineWidth: selected ? 1.5 : 1))
                .frame(width: 36, height: 36)
            if asset != nil || (sym ?? "").isEmpty == false {
                TemplateIcon(assetIcon: asset, sfSymbol: sym ?? "questionmark",
                             tint: tint, size: 20)
            } else {
                Text("∅").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .help(label)
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
                         "Native Claude Code uses whitelist only. To block parts of git — do NOT grant `git:*`, pick the precise presets below.")

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
            sectionLabel("MCP servers", "Configured MCP servers. Each agent must be granted access explicitly — nothing is inherited by default.")
            if state.agentsVM.availableMCPServers.isEmpty {
                Text("No MCP servers configured in ~/.claude.json. Configure MCP in Claude Code first.")
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
                .help("Universal wildcard — the agent will get access to every MCP tool of every server")

            sectionLabel("Other tools", "Extra tool expressions, comma-separated. For rare cases.")
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
        .help("\(server.name) MCP server (scope: \(server.scope)). Will add mcp__\(server.name)__* to the agent's tools.")
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
                .help("Open the marketplace with 177+ plugins — each can add new skills")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredSkills) { skill in
                        skillRow(skill)
                    }
                    if filteredSkills.isEmpty {
                        Text(state.agentsVM.availableSkills.isEmpty
                             ? "No skills yet — click 'Browse plugins' to install plugins with skills"
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
        guard !didLoad else { return }
        didLoad = true

        guard let agent = editing else {
            // New agent — pre-select all configured MCP servers by default.
            selectedMCPServers = Set(state.agentsVM.availableMCPServers.map(\.name))
            return
        }
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

        // Icon — saved frontmatter wins, otherwise fall back to template match by name.
        let descriptor = AgentTemplate.iconDescriptor(for: agent)
        iconAsset = agent.iconAsset ?? descriptor.asset
        iconSymbol = agent.iconSymbol ?? (descriptor.asset == nil ? descriptor.symbol : "")
        iconColor = agent.iconColor ?? (AgentTemplate.match(agentName: agent.name)?.color ?? "blue")
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
        let newName = name.trimmingCharacters(in: .whitespaces)
        let agentsDir = state.container.agentRepository.agentsDirectory()
        let memDir = agentsDir.appendingPathComponent("memory")
        do {
            // 1. If renaming an existing agent — move files + Keychain, rewrite tools paths.
            var tools = collectTools()
            var prompt = systemPrompt
            if let editing, editing.name != newName, !newName.isEmpty {
                try AgentRename.renameArtifacts(from: editing.name, to: newName, agentsDir: agentsDir)
                tools = AgentRename.rewriteTools(tools, from: editing.name, to: newName, memDir: memDir)
                prompt = AgentRename.rewritePrompt(prompt, from: editing.name, to: newName)
            }
            // 2. Save .md with up-to-date tools + prompt (AgentWriter rebuilds Memory / Variables blocks).
            let url = try state.container.agentRepository.save(
                name: newName,
                description: description,
                model: model,
                tools: tools,
                systemPrompt: prompt,
                skills: chosenSkills,
                overwrite: editing != nil
            )
            // 3. Inject icon-* frontmatter (AgentRepository signature doesn't take them yet).
            try AgentRename.patchIconFrontmatter(
                at: url,
                iconAsset: iconAsset,
                iconSymbol: iconSymbol,
                iconColor: iconColor
            )
            state.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
