import SwiftUI

/// Project-wide preset: one switch gives all agents broad local permissions
/// (read/write files, run bash, search web) while denying mutations to external
/// systems (DB, Jira/Confluence, git push, package publish, MCP writes).
///
/// Backed by `<project>/.claude/settings.local.json` — applies to every agent
/// in the project. See `SafeAutopilotPolicy`.
struct SafeAutopilotCard: View {
    let project: ClaudeProject

    @State private var enabled: Bool = false
    @State private var showDetails: Bool = false
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Safe autopilot",
                subtitle: enabled
                    ? "No approval prompts — only external writes (DB, Jira/Confluence, git push, MCP writes) are blocked"
                    : "Off — each agent uses its own permissions",
                icon: "shield.lefthalf.filled",
                trailing: AnyView(
                    Toggle("", isOn: Binding(
                        get: { enabled },
                        set: { apply($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(project.isGlobal)
                )
            )

            if project.isGlobal {
                Text("Available for real projects only — the global scope has no `settings.local.json`.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            } else {
                summaryRow
                if showDetails {
                    detailsBlock
                }
                if let lastError {
                    Text(lastError)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.danger)
                }
            }
        }
        .designCard()
        .onAppear { enabled = SafeAutopilotPolicy.isActive(in: project) }
        .onChange(of: project.id) { _, _ in
            enabled = SafeAutopilotPolicy.isActive(in: project)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: DS.Space.s) {
            Label("\(SafeAutopilotPolicy.allow.count) allowed",
                  systemImage: "checkmark.shield.fill")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Color.success)
            Label("\(SafeAutopilotPolicy.deny.count) denied",
                  systemImage: "xmark.shield.fill")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Color.danger)
            Spacer()
            Button {
                showDetails.toggle()
            } label: {
                Label(showDetails ? "Hide list" : "Show list",
                      systemImage: showDetails ? "chevron.up" : "chevron.down")
                    .font(DS.Typo.caption)
            }
            .buttonStyle(SubtleTextButtonStyle())
        }
    }

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            patternGroup(
                title: "Allowed",
                color: DS.Color.success,
                patterns: SafeAutopilotPolicy.allow
            )
            patternGroup(
                title: "Denied (external writes)",
                color: DS.Color.danger,
                patterns: SafeAutopilotPolicy.deny
            )
        }
        .padding(.top, DS.Space.xs)
    }

    private func patternGroup(title: String, color: Color, patterns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.Typo.captionMedium)
                .foregroundStyle(color)
            FlowLayout(spacing: 4) {
                ForEach(patterns, id: \.self) { p in
                    Text(p)
                        .font(DS.Typo.monoSmall)
                        .padding(.horizontal, DS.Space.s).padding(.vertical, 3)
                        .foregroundStyle(color)
                        .background(
                            Capsule()
                                .fill(color.opacity(0.10))
                                .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
                        )
                }
            }
        }
    }

    private func apply(_ on: Bool) {
        let prev = enabled
        enabled = on
        lastError = nil
        do {
            if on {
                try SafeAutopilotPolicy.enable(in: project)
            } else {
                try SafeAutopilotPolicy.disable(in: project)
            }
        } catch {
            enabled = prev
            lastError = "Couldn't write settings.local.json: \(error.localizedDescription)"
        }
    }
}
