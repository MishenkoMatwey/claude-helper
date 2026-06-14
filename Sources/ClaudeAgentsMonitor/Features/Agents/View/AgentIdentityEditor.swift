import SwiftUI
import AppKit

/// Sheet for editing an agent's name and icon (asset + color).
/// On save: rewrites <name>.md frontmatter; if the name changed, renames the .md plus
/// every sibling (`memory/<name>.md`, `.playbooks.md`, `.context.md`, `.vars.json`,
/// `.schema.md`) and re-keys the Keychain service.
struct AgentIdentityEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let agent: Agent

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var iconAsset: String? = nil
    @State private var iconSymbol: String = ""
    @State private var iconColor: String = "blue"
    @State private var error: String?
    @State private var didInit: Bool = false

    private let brandAssets = ["clussters", "git", "jira", "confluence", "figma", "database", "github", "gitlab", "chrome", "vscode", "intellij"]
    private let sfSymbols = [
        "person.crop.circle", "bolt.fill", "checklist", "cylinder.split.1x2.fill",
        "doc.richtext", "arrow.triangle.branch", "paintbrush.pointed.fill",
        "network", "shield.fill", "magnifyingglass", "wand.and.stars",
        "gearshape.fill", "terminal.fill", "globe", "lock.fill"
    ]
    private let colors = ["blue", "orange", "purple", "green", "red", "gray"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    previewCard
                    identityFields
                    iconPickerSection
                    colorPickerSection
                    if let err = error {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(DS.Color.danger).font(DS.Typo.caption)
                    }
                }
                .padding(DS.Space.l)
            }
            .background(DS.Color.bg)
            Divider()
            footer
        }
        .frame(width: 640, height: 720)
        .onAppear(perform: initIfNeeded)
    }

    private var header: some View {
        HStack {
            Text("Edit identity — \(agent.name)").font(DS.Typo.title)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SubtleTextButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(DS.Space.l)
        .background(DS.Color.surface)
    }

    private var previewCard: some View {
        let color = AgentTemplate.swiftUIColor(iconColor)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)
                TemplateIcon(assetIcon: iconAsset,
                             sfSymbol: iconSymbol.isEmpty ? "person.crop.circle" : iconSymbol,
                             tint: color, size: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? agent.name : name).font(DS.Typo.headline)
                Text(description.isEmpty ? "(no description)" : description)
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .designCard()
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Name & description", subtitle: "Lowercase, digits, hyphen — used as filename",
                icon: "person.crop.circle", trailing: AnyView(EmptyView())
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(DS.Typo.captionMedium)
                TextField("e.g. ui-reviewer", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typo.monoSmall)
                if name != agent.name && !name.isEmpty {
                    Label("Renaming will move <name>.md, memory/<name>.*, .vars.json, .schema.md and re-key Keychain.",
                          systemImage: "info.circle")
                        .font(DS.Typo.caption).foregroundStyle(DS.Color.warning)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(DS.Typo.captionMedium)
                TextField("Short purpose", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
        }
        .designCard()
    }

    private var iconPickerSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Icon", subtitle: "Brand asset (recommended) or SF Symbol",
                icon: "paintpalette.fill", trailing: AnyView(EmptyView())
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("Brand").font(DS.Typo.captionMedium)
                let tint = AgentTemplate.swiftUIColor(iconColor)
                FlowLayout(spacing: 6) {
                    ForEach(brandAssets, id: \.self) { a in
                        Button {
                            iconAsset = a
                            iconSymbol = ""
                        } label: {
                            iconChip(asset: a, sym: "", selected: iconAsset == a, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        iconAsset = nil
                    } label: {
                        Text("none")
                            .font(DS.Typo.monoSmall)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                Capsule().fill(iconAsset == nil ? tint.opacity(0.2) : DS.Color.surfaceElevated)
                                    .overlay(Capsule().stroke(iconAsset == nil ? tint : DS.Color.border, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("SF Symbol fallback").font(DS.Typo.captionMedium)
                let tint = AgentTemplate.swiftUIColor(iconColor)
                FlowLayout(spacing: 6) {
                    ForEach(sfSymbols, id: \.self) { s in
                        Button {
                            iconSymbol = s
                            iconAsset = nil
                        } label: {
                            iconChip(asset: nil, sym: s, selected: iconSymbol == s && iconAsset == nil, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 4) {
                    Text("Custom:").font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    TextField("any.sf.symbol.name", text: $iconSymbol)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Typo.monoSmall)
                }
            }
        }
        .designCard()
    }

    private func iconChip(asset: String?, sym: String, selected: Bool, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? tint.opacity(0.20) : DS.Color.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? tint : DS.Color.border, lineWidth: selected ? 1.5 : 1)
                )
                .frame(width: 36, height: 36)
            TemplateIcon(assetIcon: asset, sfSymbol: sym.isEmpty ? "questionmark" : sym,
                         tint: tint, size: 20)
        }
    }

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Color", subtitle: "Used for the chip tint",
                icon: "drop.fill", trailing: AnyView(EmptyView())
            )
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { c in
                    let tint = AgentTemplate.swiftUIColor(c)
                    Button {
                        iconColor = c
                    } label: {
                        Circle()
                            .fill(tint)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().stroke(iconColor == c ? Color.primary : Color.clear, lineWidth: 2)
                            )
                            .overlay(
                                Image(systemName: iconColor == c ? "checkmark" : "")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 10, weight: .bold))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(c)
                }
            }
        }
        .designCard()
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SubtleTextButtonStyle())
            Button("Save") { save() }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
        }
        .padding(DS.Space.l)
        .background(DS.Color.surface)
    }

    private func initIfNeeded() {
        guard !didInit else { return }
        didInit = true
        name = agent.name
        description = agent.description
        let desc = AgentTemplate.iconDescriptor(for: agent)
        iconAsset = desc.asset
        iconSymbol = agent.iconSymbol ?? (desc.asset == nil ? desc.symbol : "")
        iconColor = agent.iconColor ?? (AgentTemplate.match(agentName: agent.name)?.color ?? "blue")
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            // 1. Rename files + Keychain if name changed.
            if trimmed != agent.name {
                try renameAgentArtifacts(from: agent.name, to: trimmed)
            }
            // 2. Re-save .md with new frontmatter (icon-asset, icon-symbol, icon-color).
            var tools = agent.tools
            renameToolsInPlace(&tools, from: agent.name, to: trimmed)
            _ = try state.container.agentRepository.save(
                name: trimmed,
                description: description,
                model: agent.model ?? "default",
                tools: tools,
                systemPrompt: rewriteSystemPrompt(agent.promptWithoutInjectedBlocks,
                                                  from: agent.name, to: trimmed),
                skills: [],
                overwrite: true
            )
            // AgentWriter.save signature includes optional icon params — patch via re-write below
            try patchIconFrontmatter(for: trimmed)
            state.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func mutableTools() -> [String] { agent.tools }

    /// Walk an existing tools list and rewrite `Edit(.../<old>.<suffix>)` paths to `<new>.<suffix>`.
    private func renameToolsInPlace(_ tools: inout [String], from old: String, to new: String) {
        guard old != new else { return }
        let memDir = state.container.agentRepository.agentsDirectory()
            .appendingPathComponent("memory").path
        let suffixes = [".md", ".playbooks.md", ".context.md"]
        tools = tools.map { tool in
            var t = tool
            for suf in suffixes {
                t = t.replacingOccurrences(of: "\(memDir)/\(old)\(suf)",
                                           with: "\(memDir)/\(new)\(suf)")
            }
            return t
        }
    }

    /// Throwing wrapper, kept separate in case we need to bail before save.
    private func renameTools(in tools: inout [String], from old: String, to new: String) throws {
        renameToolsInPlace(&tools, from: old, to: new)
    }

    /// Replace `<old>.<suffix>` substrings inside the system prompt (Memory protocol paths etc).
    private func rewriteSystemPrompt(_ prompt: String, from old: String, to new: String) -> String {
        guard old != new else { return prompt }
        var s = prompt
        for suf in [".md", ".playbooks.md", ".context.md", ".vars.json", ".schema.md"] {
            s = s.replacingOccurrences(of: "\(old)\(suf)", with: "\(new)\(suf)")
        }
        // also replace bare " — <old>" mentions and self-references in stub texts.
        s = s.replacingOccurrences(of: "(\(old))", with: "(\(new))")
        return s
    }

    /// After agentRepository.save (which uses AgentWriter without icon params) — re-write the
    /// frontmatter of the freshly-saved file to inject icon-asset / icon-symbol / icon-color lines.
    private func patchIconFrontmatter(for newName: String) throws {
        let url = state.container.agentRepository.agentsDirectory()
            .appendingPathComponent("\(newName).md")
        var src = try String(contentsOf: url, encoding: .utf8)
        // Strip existing icon-* lines.
        let stripPatterns = ["\nicon-asset: .*", "\nicon-symbol: .*", "\nicon-color: .*"]
        for p in stripPatterns {
            if let r = try? NSRegularExpression(pattern: p) {
                let range = NSRange(src.startIndex..., in: src)
                src = r.stringByReplacingMatches(in: src, range: range, withTemplate: "")
            }
        }
        // Insert new icon-* lines before the closing `---` of frontmatter.
        var lines: [String] = []
        if let v = iconAsset, !v.isEmpty  { lines.append("icon-asset: \(v)") }
        let symTrimmed = iconSymbol.trimmingCharacters(in: .whitespaces)
        if !symTrimmed.isEmpty            { lines.append("icon-symbol: \(symTrimmed)") }
        if !iconColor.isEmpty             { lines.append("icon-color: \(iconColor)") }
        guard !lines.isEmpty else {
            try src.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        // Find frontmatter closing.
        if let openRange = src.range(of: "---\n"),
           let closeRange = src.range(of: "\n---\n", range: openRange.upperBound..<src.endIndex) {
            let inject = "\n" + lines.joined(separator: "\n")
            src.insert(contentsOf: inject, at: closeRange.lowerBound)
            try src.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func renameAgentArtifacts(from old: String, to new: String) throws {
        let dir = state.container.agentRepository.agentsDirectory()
        let memDir = dir.appendingPathComponent("memory")
        let fm = FileManager.default

        // .md primary
        let srcMd = dir.appendingPathComponent("\(old).md")
        let dstMd = dir.appendingPathComponent("\(new).md")
        if fm.fileExists(atPath: dstMd.path) {
            throw NSError(domain: "Identity", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Agent '\(new)' already exists — pick a different name."])
        }
        if fm.fileExists(atPath: srcMd.path) {
            try fm.moveItem(at: srcMd, to: dstMd)
        }
        for suf in [".md", ".playbooks.md", ".context.md", ".vars.json", ".schema.md"] {
            let src = memDir.appendingPathComponent("\(old)\(suf)")
            let dst = memDir.appendingPathComponent("\(new)\(suf)")
            if fm.fileExists(atPath: src.path) {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.moveItem(at: src, to: dst)
            }
            // .schema.md may live next to .md (not in memory/) — handle both.
            if suf == ".schema.md" {
                let srcSibling = dir.appendingPathComponent("\(old)\(suf)")
                let dstSibling = dir.appendingPathComponent("\(new)\(suf)")
                if fm.fileExists(atPath: srcSibling.path) {
                    if fm.fileExists(atPath: dstSibling.path) { try fm.removeItem(at: dstSibling) }
                    try fm.moveItem(at: srcSibling, to: dstSibling)
                }
            }
        }
        // Keychain: re-key every entry from claude-agent-<pid>-<old> to claude-agent-<pid>-<new>.
        let oldSvc = AgentVariablesService.keychainService(for: old)
        let newSvc = AgentVariablesService.keychainService(for: new)
        for key in AgentVariablesService.listKeychainKeys(service: oldSvc) {
            if let value = AgentVariablesService.readKeychain(key: key, service: oldSvc) {
                try? AgentVariablesService.saveKeychain(key: key, value: value, service: newSvc)
                try? AgentVariablesService.removeKeychain(key: key, service: oldSvc)
            }
        }
    }
}
