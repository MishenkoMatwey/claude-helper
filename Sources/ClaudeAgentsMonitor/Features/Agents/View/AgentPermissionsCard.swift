import SwiftUI

struct AgentPermissionsCard: View {
    @EnvironmentObject var state: AppState
    let agent: Agent

    @State private var entries: [PermissionEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Permissions",
                subtitle: "\(entries.count) effective rules — own + inherited",
                icon: "key.fill",
                trailing: AnyView(
                    Button { reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Reload from disk")
                )
            )
            ForEach(scopes, id: \.self) { scope in
                scopeBlock(scope)
            }
            if entries.isEmpty {
                Text("No permissions yet — agent inherits everything from parent (if no `tools:` set in .md), nothing if set.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    .padding(.vertical, DS.Space.s)
            }
        }
        .designCard()
        .onAppear(perform: reload)
        .onChange(of: agent.id) { _, _ in reload() }
    }

    private var scopes: [PermissionEntry.Scope] {
        PermissionEntry.Scope.allCases.filter { scope in
            entries.contains { $0.scope == scope }
        }
    }

    @ViewBuilder
    private func scopeBlock(_ scope: PermissionEntry.Scope) -> some View {
        let scopeEntries = entries.filter { $0.scope == scope }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: scopeIcon(scope))
                    .foregroundStyle(scopeColor(scope))
                    .font(.system(size: 11, weight: .semibold))
                Text(scopeTitle(scope))
                    .font(DS.Typo.captionMedium)
                Text("(\(scopeEntries.count))")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Text(scopeOrigin(scope))
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            FlowLayout(spacing: 4) {
                ForEach(scopeEntries) { entry in
                    permissionChip(entry)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func permissionChip(_ entry: PermissionEntry) -> some View {
        let color = scopeColor(entry.scope)
        return HStack(spacing: 4) {
            Text(entry.pattern)
                .font(DS.Typo.monoSmall)
                .lineLimit(1)
            if entry.scope != .agent && !isDenyScope(entry.scope) {
                Button {
                    promote(entry.pattern)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(color)
                .help("Promote to agent's own tools — закрепить за этим агентом")
            }
        }
        .padding(.horizontal, DS.Space.s).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(
            Capsule().fill(color.opacity(0.10))
                .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
        )
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
        entries = state.container.permissions.load(for: agent, in: state.projectsVM.currentProject)
    }

    private func promote(_ pattern: String) {
        try? state.container.permissions.promote(pattern: pattern, into: agent)
        state.refresh()
        reload()
    }
}
