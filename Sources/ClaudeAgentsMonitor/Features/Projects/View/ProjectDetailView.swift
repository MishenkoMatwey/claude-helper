import SwiftUI
import AppKit

struct ProjectDetailView: View {
    @EnvironmentObject var state: AppState
    let project: ClaudeProject
    let onSelect: (DetailSelection) -> Void

    private var isCurrent: Bool { state.projectsVM.currentProject.id == project.id }
    private var counts: ProjectCounts { project.counts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                hero
                statsRow
                quickActionsCard
                SafeAutopilotCard(project: project)
                AgentRunsCard(projectPath: project.path)
                if !project.isGlobal {
                    ReviewQueueCard(projectPath: project.path)
                }
                agentsCard
                autoRefreshCard
                techCard
            }
            .padding(DS.Space.xl)
        }
        .background(DS.Color.bg)
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: DS.Space.l) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.l)
                    .fill(LinearGradient(
                        colors: project.isGlobal
                            ? [DS.Color.accent, DS.Color.purple]
                            : [DS.Color.success, DS.Color.teal],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                Image(systemName: project.isGlobal ? "house.fill" : "folder.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 28, weight: .semibold))
            }
            .shadow(color: DS.Color.accent.opacity(0.3), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(DS.Typo.displayLarge)
                Text(project.path)
                    .font(DS.Typo.mono)
                    .foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: DS.Space.s) {
                Button {
                    NSWorkspace.shared.open(project.url)
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }
                .buttonStyle(OutlineButtonStyle())
                .help("Open project folder in Finder")
                if !project.isGlobal {
                    Button {
                        state.projectsVM.renamingProject = project
                    } label: { Label("Rename", systemImage: "pencil") }
                        .buttonStyle(OutlineButtonStyle())
                        .help("Change display name")
                    Button(role: .destructive) {
                        state.projectsVM.removeProject(project)
                    } label: { Label("Remove", systemImage: "trash") }
                        .buttonStyle(OutlineButtonStyle(tint: DS.Color.danger))
                        .help("Remove project from the app list (files stay on disk)")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: DS.Space.l) {
            statCard("Agents", value: counts.agents, color: DS.Color.accent, icon: "person.2.fill")
            statCard("Total assets", value: counts.total, color: DS.Color.textSecondary, icon: "square.stack.3d.up.fill")
        }
    }

    private func statCard(_ title: String, value: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(DS.Typo.captionMedium).foregroundStyle(DS.Color.textSecondary)
                Spacer()
            }
            Text("\(value)").font(DS.Typo.displayLarge).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    // MARK: Quick actions

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            DesignSectionHeader(title: "Quick actions", icon: "wand.and.stars")
            HStack(spacing: DS.Space.s) {
                quickAction(
                    label: "New agent", icon: "person.crop.circle.badge.plus",
                    tint: DS.Color.accent, help: "Create an agent in this project"
                ) {
                    if !isCurrent { state.projectsVM.switchProject(project) }
                    state.agentsVM.showNewAgentSheet = true
                }
            }
        }
        .designCard()
    }

    private func quickAction(label: String, icon: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                Text(label).font(DS.Typo.captionMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m)
                    .fill(tint.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(tint.opacity(0.25), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Agents

    private var agentsCard: some View {
        listCard(
            title: "Agents", count: counts.agents, icon: "person.2.fill", tint: DS.Color.accent,
            emptyText: "No agents yet",
            addLabel: "New agent"
        ) {
            state.agentsVM.showNewAgentSheet = true
        } content: {
            ForEach(state.agentsVM.agents) { a in
                let isOrch = a.isOrchestrator
                let desc = AgentTemplate.iconDescriptor(for: a)
                listRow(
                    icon: isOrch ? "bolt.fill" : desc.symbol,
                    iconColor: isOrch ? DS.Color.warning : desc.color,
                    title: a.name,
                    subtitle: a.description.isEmpty ? "(no description)" : a.description,
                    accessory: isOrch ? "auto" : nil,
                    accessoryColor: DS.Color.warning
                ) {
                    onSelect(.agent(a.id))
                }
            }
        }
    }

    private var autoRefreshStatus: AutoRefreshStatus {
        AutoRefreshStatus.load(projectPath: URL(fileURLWithPath: project.path))
    }

    private var autoRefreshCard: some View {
        let status = autoRefreshStatus
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(title: "Auto-refresh", icon: "arrow.triangle.2.circlepath")

            // Schedule row
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(status.launchAgentLabel != nil ? DS.Color.success : DS.Color.textTertiary)
                if let label = status.launchAgentLabel {
                    Text(label).font(DS.Typo.bodyMedium)
                    if let when = status.nextScheduledRun {
                        Text("·").foregroundStyle(DS.Color.textTertiary)
                        Text(when).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                } else {
                    Text("No LaunchAgent configured")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }

            // Last successful refresh per agent
            if status.lastRefreshByAgent.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("No successful refresh yet")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            } else {
                let dateFmt: DateFormatter = {
                    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
                }()
                let latest = status.lastSuccessfulRefresh.map(dateFmt.string(from:)) ?? "—"
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Color.success)
                    Text("Last successful refresh: \(latest)")
                        .font(DS.Typo.bodyMedium)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(status.lastRefreshByAgent.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                        HStack(spacing: 4) {
                            Text("·").foregroundStyle(DS.Color.textTertiary)
                            Text(entry.key).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                            Spacer()
                            Text(dateFmt.string(from: entry.value))
                                .font(DS.Typo.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
                .padding(.leading, 22)
            }

            Divider().padding(.vertical, 2)

            // Backups
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .foregroundStyle(status.backups.isEmpty ? DS.Color.textTertiary : DS.Color.accent)
                Text("Backups: \(status.backups.count)")
                    .font(DS.Typo.bodyMedium)
                if let last = status.lastBackup {
                    Text("·").foregroundStyle(DS.Color.textTertiary)
                    let bf: DateFormatter = {
                        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
                    }()
                    Text("latest \(bf.string(from: last.date))")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                if let last = status.lastBackup {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([last.path])
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                }
            }

            if !status.backups.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    let bf: DateFormatter = {
                        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
                    }()
                    ForEach(status.backups.prefix(5)) { b in
                        HStack(spacing: 4) {
                            Text("·").foregroundStyle(DS.Color.textTertiary)
                            Text(b.id).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                            Spacer()
                            Text("\(b.fileCount) files · \(bf.string(from: b.date))")
                                .font(DS.Typo.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                    if status.backups.count > 5 {
                        Text("… and \(status.backups.count - 5) more")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                            .padding(.leading, 14)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(DS.Space.m)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).stroke(DS.Color.border))
    }

    private var techCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(title: "Tech", icon: "info.circle")
            techRow("Agents folder", "\(project.agentPaths.agentsRoot.path)")
            techRow("Memory folder", "\(project.agentPaths.memoryDir.path)")
            techRow("Workflows folder", "\(project.agentPaths.workflowsDir.path)")
            techRow("Schedules folder", "\(project.agentPaths.schedulesDir.path)")
            techRow("Keychain prefix", "claude-agent-\(project.agentPaths.projectId)-…")
        }
        .designCard()
    }

    private func techRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary).frame(width: 130, alignment: .leading)
            Text(value).font(DS.Typo.monoSmall).foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled).lineLimit(2)
            Spacer()
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func listCard<C: View>(
        title: String, count: Int, icon: String, tint: Color,
        emptyText: String, addLabel: String,
        addAction: @escaping () -> Void,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: title, subtitle: "\(count) total", icon: icon,
                trailing: AnyView(
                    Button {
                        addAction()
                    } label: {
                        Label(addLabel, systemImage: "plus")
                            .font(DS.Typo.captionMedium)
                    }
                    .buttonStyle(GhostButtonStyle(tint: tint))
                    .help("Create a new \(title.lowercased())")
                )
            )
            if count == 0 {
                EmptyState(
                    icon: icon,
                    title: emptyText,
                    subtitle: "Create your first \(title.lowercased()) using the button above",
                    actionTitle: addLabel,
                    action: addAction
                )
                .frame(maxWidth: .infinity)
            } else {
                content()
            }
        }
        .designCard()
    }

    private func listRow(
        icon: String, iconColor: Color,
        title: String, subtitle: String,
        accessory: String?, accessoryColor: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: icon).foregroundStyle(iconColor).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title).font(DS.Typo.bodyMedium)
                        if let accessory, let accessoryColor {
                            StatusBadge(text: accessory, color: accessoryColor)
                        }
                    }
                    Text(subtitle).font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.vertical, 4).padding(.horizontal, DS.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
