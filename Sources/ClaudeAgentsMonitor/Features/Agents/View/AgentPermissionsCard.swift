import SwiftUI

struct AgentPermissionsCard: View {
    @EnvironmentObject var state: AppState
    let agent: Agent

    @State private var entries: [PermissionEntry] = []
    @State private var newPattern: String = ""
    /// Preserves chip order per scope so toggling doesn't reshuffle items.
    /// Patterns toggled off stay in this list as grayed chips.
    @State private var chipOrder: [PermissionEntry.Scope: [String]] = [:]
    /// How many settings.local.json rules don't match any agent's frontmatter.
    @State private var orphanCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Permissions",
                subtitle: orphanCount > 0
                    ? "\(entries.count) active · \(orphanCount) project approvals not assigned to any agent"
                    : "\(entries.count) active — click a chip to toggle",
                icon: "key.fill",
                trailing: AnyView(EmptyView())
            )
            ForEach(scopes, id: \.self) { scope in
                scopeBlock(scope)
            }
            if entries.isEmpty {
                Text("No permissions yet — agent inherits everything from parent (if no `tools:` set in .md), nothing if set.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    .padding(.vertical, DS.Space.s)
            }
            addRow
        }
        .designCard()
        .onAppear(perform: reload)
        .onChange(of: agent.id) { _, _ in reload() }
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").foregroundStyle(DS.Color.accent)
            TextField("Add custom pattern (e.g. Bash(npm:*) or Read)", text: $newPattern)
                .textFieldStyle(.roundedBorder)
                .font(DS.Typo.monoSmall)
                .onSubmit(addCustom)
            Button("Add") { addCustom() }
                .buttonStyle(GhostButtonStyle())
                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.top, DS.Space.xs)
    }

    private var scopes: [PermissionEntry.Scope] {
        PermissionEntry.Scope.allCases.filter { !(chipOrder[$0]?.isEmpty ?? true) }
    }

    @ViewBuilder
    private func scopeBlock(_ scope: PermissionEntry.Scope) -> some View {
        let orderedPatterns = chipOrder[scope] ?? []
        let activeSet = Set(entries.filter { $0.scope == scope }.map(\.pattern))
        let isSettings = (scope == .projectAllow || scope == .userAllow
                       || scope == .projectDeny || scope == .userDeny)
        let generalizableCount = isSettings
            ? activeSet.filter { state.container.permissions.generalize($0) != $0 }.count
            : 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: scopeIcon(scope))
                    .foregroundStyle(scopeColor(scope))
                    .font(.system(size: 11, weight: .semibold))
                Text(scopeTitle(scope))
                    .font(DS.Typo.captionMedium)
                Text("(\(activeSet.count))")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                if generalizableCount > 0 {
                    Button {
                        generalizeAll(in: scope)
                    } label: {
                        Label("Generalize \(generalizableCount)", systemImage: "wand.and.stars")
                            .font(DS.Typo.caption)
                    }
                    .buttonStyle(SubtleTextButtonStyle())
                    .help("Replace JWTs, UUIDs and long tokens with `*` in every rule of this scope. Original rules will be removed.")
                }
                Spacer()
                Text(scopeOrigin(scope))
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            FlowLayout(spacing: 4) {
                ForEach(orderedPatterns, id: \.self) { pattern in
                    permissionChip(
                        PermissionEntry(pattern: pattern, scope: scope),
                        enabled: activeSet.contains(pattern)
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func permissionChip(_ entry: PermissionEntry, enabled: Bool) -> some View {
        let baseColor = scopeColor(entry.scope)
        let fg = enabled ? baseColor : DS.Color.textTertiary
        let bg = enabled ? baseColor.opacity(0.10) : DS.Color.textTertiary.opacity(0.10)
        let stroke = enabled ? baseColor.opacity(0.3) : DS.Color.textTertiary.opacity(0.25)
        let generalized = state.container.permissions.generalize(entry.pattern)
        let canGeneralize = generalized != entry.pattern
        let inSettings = entry.scope == .projectAllow || entry.scope == .userAllow
                      || entry.scope == .projectDeny || entry.scope == .userDeny
        return Button {
            toggle(entry, enabled: enabled)
        } label: {
            HStack(spacing: 4) {
                if inSettings && enabled {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Color.warning)
                        .help("Lives in settings.local.json — right-click to move into agent")
                }
                Text(entry.pattern)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(DS.Typo.monoSmall)
            .strikethrough(!enabled, color: DS.Color.textTertiary)
            .padding(.horizontal, DS.Space.s).padding(.vertical, 3)
            .foregroundStyle(fg)
            .background(
                Capsule().fill(bg)
                    .overlay(Capsule().stroke(stroke, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .help(enabled ? "Click to toggle off — \(removeHelp(for: entry.scope))"
                      : "Click to toggle on — \(addHelp(for: entry.scope))")
        .contextMenu {
            if inSettings && enabled {
                Button {
                    move(entry)
                } label: {
                    Label("Move into agent's .md", systemImage: "arrow.right.to.line")
                }
                Button {
                    copyIntoAgent(entry)
                } label: {
                    Label("Copy into agent (keep in settings)", systemImage: "doc.on.doc")
                }
                Divider()
            }
            if canGeneralize {
                Button {
                    replace(entry, with: generalized)
                } label: {
                    Label("Generalize → \(generalized.prefix(60))…", systemImage: "wand.and.stars")
                }
                .help("Replace JWTs, UUIDs and long tokens with `*` so the rule survives token rotation.")
            }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(entry.pattern, forType: .string)
            } label: {
                Label("Copy pattern", systemImage: "doc.on.clipboard")
            }
        }
    }

    /// Batch: rewrite every generalizable pattern in this scope to its wildcard form.
    /// Same-target rules are deduplicated.
    private func generalizeAll(in scope: PermissionEntry.Scope) {
        let project = state.projectsVM.currentProject
        let originals = (chipOrder[scope] ?? []).filter { Set(entries.filter { $0.scope == scope }.map(\.pattern)).contains($0) }
        var seenNew = Set<String>()
        for original in originals {
            let generalized = state.container.permissions.generalize(original)
            guard generalized != original else { continue }
            do {
                switch scope {
                case .agent:
                    try state.container.permissions.removeFromAgent(pattern: original, agent: agent)
                    if !seenNew.contains(generalized) {
                        try state.container.permissions.addCustom(pattern: generalized, agent: agent)
                    }
                case .projectAllow, .projectDeny, .userAllow, .userDeny:
                    try state.container.permissions.removeFromSettings(pattern: original, scope: scope, in: project)
                    if !seenNew.contains(generalized) {
                        try state.container.permissions.addToSettings(pattern: generalized, scope: scope, in: project)
                    }
                }
                seenNew.insert(generalized)
            } catch {
                continue
            }
        }
        reload()
    }

    private func move(_ entry: PermissionEntry) {
        do {
            try state.container.permissions.move(
                pattern: entry.pattern,
                fromScope: entry.scope,
                into: agent,
                in: state.projectsVM.currentProject
            )
        } catch {
            // ignore — reload will re-sync UI
        }
        reload()
    }

    private func copyIntoAgent(_ entry: PermissionEntry) {
        try? state.container.permissions.promote(pattern: entry.pattern, into: agent)
        reload()
    }

    /// Used by "Generalize" — write the new pattern into the same scope, remove the original.
    private func replace(_ entry: PermissionEntry, with newPattern: String) {
        do {
            switch entry.scope {
            case .agent:
                try state.container.permissions.removeFromAgent(pattern: entry.pattern, agent: agent)
                try state.container.permissions.addCustom(pattern: newPattern, agent: agent)
            case .projectAllow, .projectDeny, .userAllow, .userDeny:
                let project = state.projectsVM.currentProject
                try state.container.permissions.removeFromSettings(
                    pattern: entry.pattern, scope: entry.scope, in: project)
                try state.container.permissions.addToSettings(
                    pattern: newPattern, scope: entry.scope, in: project)
            }
        } catch {
            // ignore — reload below
        }
        reload()
    }

    private func removeHelp(for scope: PermissionEntry.Scope) -> String {
        switch scope {
        case .agent: return "removes from \(agent.name).md"
        case .projectAllow, .projectDeny: return "removes from project settings.local.json"
        case .userAllow, .userDeny: return "removes from ~/.claude/settings.json"
        }
    }

    private func addHelp(for scope: PermissionEntry.Scope) -> String {
        switch scope {
        case .agent: return "restores in \(agent.name).md"
        case .projectAllow, .projectDeny: return "restores in project settings.local.json"
        case .userAllow, .userDeny: return "restores in ~/.claude/settings.json"
        }
    }

    private func isDenyScope(_ scope: PermissionEntry.Scope) -> Bool {
        scope == .projectDeny || scope == .userDeny
    }

    private func scopeTitle(_ scope: PermissionEntry.Scope) -> String {
        switch scope {
        case .agent: return "Agent's own tools"
        case .projectAllow: return "Project allow"
        case .projectDeny: return "Project DENY"
        case .userAllow: return "User (global) allow"
        case .userDeny: return "User (global) DENY"
        }
    }

    private func scopeOrigin(_ scope: PermissionEntry.Scope) -> String {
        switch scope {
        case .agent: return "in \(agent.name).md"
        case .projectAllow, .projectDeny: return "settings.local.json"
        case .userAllow, .userDeny: return "~/.claude/settings.json"
        }
    }

    private func scopeIcon(_ scope: PermissionEntry.Scope) -> String {
        switch scope {
        case .agent: return "person.crop.circle"
        case .projectAllow, .userAllow: return "checkmark.shield.fill"
        case .projectDeny, .userDeny: return "xmark.shield.fill"
        }
    }

    private func scopeColor(_ scope: PermissionEntry.Scope) -> Color {
        switch scope {
        case .agent: return DS.Color.accent
        case .projectAllow: return DS.Color.success
        case .projectDeny: return DS.Color.danger
        case .userAllow: return DS.Color.info
        case .userDeny: return DS.Color.warning
        }
    }

    private func reload() {
        let all = state.container.permissions.load(for: agent, in: state.projectsVM.currentProject)
        // settings.local.json doesn't tag permissions per subagent.
        // Rules:
        //  - Show agent's own tools (scope=.agent) always.
        //  - Show settings.* chips only if the same pattern is ALSO in this agent's frontmatter
        //    (i.e. inherited+explicit — both confirm the rule for this agent).
        //  - Hide chips that live exclusively in settings.local.json — they're "orphan project
        //    approvals" and may belong to any agent or to the main Claude. Surface their count
        //    via a hint so the user knows they exist.
        let ownPatterns = Set(agent.tools)
        var orphan = 0
        entries = all.filter { e in
            switch e.scope {
            case .agent:
                return true
            case .projectAllow, .projectDeny, .userAllow, .userDeny:
                if ownPatterns.contains(e.pattern) {
                    return true
                } else {
                    orphan += 1
                    return false
                }
            }
        }
        orphanCount = orphan
        // Merge new active patterns into chipOrder (preserving prior positions).
        for entry in entries {
            var list = chipOrder[entry.scope] ?? []
            if !list.contains(entry.pattern) {
                list.append(entry.pattern)
            }
            chipOrder[entry.scope] = list
        }
        // Drop chips from chipOrder whose patterns are no longer present anywhere.
        let presentByScope = Dictionary(grouping: entries, by: \.scope)
            .mapValues { Set($0.map(\.pattern)) }
        for scope in PermissionEntry.Scope.allCases {
            let kept = presentByScope[scope] ?? []
            chipOrder[scope] = (chipOrder[scope] ?? []).filter { kept.contains($0) }
        }
    }

    private func toggle(_ entry: PermissionEntry, enabled: Bool) {
        // Optimistic UI: update entries first, then write to disk asynchronously.
        if enabled {
            entries.removeAll { $0.scope == entry.scope && $0.pattern == entry.pattern }
        } else {
            entries.append(entry)
        }
        do {
            if enabled {
                switch entry.scope {
                case .agent:
                    try state.container.permissions.removeFromAgent(pattern: entry.pattern, agent: agent)
                case .projectAllow, .projectDeny, .userAllow, .userDeny:
                    try state.container.permissions.removeFromSettings(
                        pattern: entry.pattern, scope: entry.scope,
                        in: state.projectsVM.currentProject
                    )
                }
            } else {
                switch entry.scope {
                case .agent:
                    try state.container.permissions.addCustom(pattern: entry.pattern, agent: agent)
                case .projectAllow, .projectDeny, .userAllow, .userDeny:
                    try state.container.permissions.addToSettings(
                        pattern: entry.pattern, scope: entry.scope,
                        in: state.projectsVM.currentProject
                    )
                }
            }
        } catch {
            // On error revert optimistic change by reloading from disk.
            reload()
        }
    }

    private func addCustom() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        // Optimistic insert.
        let entry = PermissionEntry(pattern: pattern, scope: .agent)
        if !entries.contains(where: { $0.scope == .agent && $0.pattern == pattern }) {
            entries.append(entry)
        }
        var list = chipOrder[.agent] ?? []
        if !list.contains(pattern) { list.append(pattern) }
        chipOrder[.agent] = list
        newPattern = ""
        try? state.container.permissions.addCustom(pattern: pattern, agent: agent)
    }
}
