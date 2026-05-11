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
                agentsCard
                workflowsCard
                schedulesCard
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
                .help("Открыть папку проекта в Finder")
                if !project.isGlobal {
                    Button {
                        state.projectsVM.renamingProject = project
                    } label: { Label("Rename", systemImage: "pencil") }
                        .buttonStyle(OutlineButtonStyle())
                        .help("Изменить display name")
                    Button(role: .destructive) {
                        state.projectsVM.removeProject(project)
                    } label: { Label("Remove", systemImage: "trash") }
                        .buttonStyle(OutlineButtonStyle(tint: DS.Color.danger))
                        .help("Удалить проект из списка app (файлы остаются на диске)")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: DS.Space.l) {
            statCard("Agents", value: counts.agents, color: DS.Color.accent, icon: "person.2.fill")
            statCard("Workflows", value: counts.workflows, color: DS.Color.purple, icon: "rectangle.connected.to.line.below")
            statCard("Schedules", value: counts.schedules, color: DS.Color.success, icon: "calendar")
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
                    tint: DS.Color.accent, help: "Создать агента в этом проекте"
                ) {
                    if !isCurrent { state.projectsVM.switchProject(project) }
                    state.agentsVM.showNewAgentSheet = true
                }
                quickAction(
                    label: "New workflow", icon: "rectangle.connected.to.line.below",
                    tint: DS.Color.purple, help: "Создать workflow"
                ) {
                    if !isCurrent { state.projectsVM.switchProject(project) }
                    state.workflowsVM.showNewWorkflowSheet = true
                }
                quickAction(
                    label: "New schedule", icon: "calendar.badge.plus",
                    tint: DS.Color.success, help: "Создать расписание"
                ) {
                    if !isCurrent { state.projectsVM.switchProject(project) }
                    state.schedulesVM.showNewScheduleSheet = true
                }
                quickAction(
                    label: "Build orchestrator", icon: "bolt.fill",
                    tint: DS.Color.warning, help: "Пересобрать orchestrator-агента из текущего состояния"
                ) {
                    if !isCurrent { state.projectsVM.switchProject(project) }
                    state.workflowsVM.generateOrchestrator()
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
            emptyText: "Агенты не созданы",
            addLabel: "New agent"
        ) {
            state.agentsVM.showNewAgentSheet = true
        } content: {
            ForEach(state.agentsVM.agents) { a in
                listRow(
                    icon: a.name == OrchestratorBuilder.agentName ? "bolt.fill" : "person.crop.circle",
                    iconColor: a.name == OrchestratorBuilder.agentName ? DS.Color.warning : DS.Color.accent,
                    title: a.name,
                    subtitle: a.description.isEmpty ? "(no description)" : a.description,
                    accessory: a.name == OrchestratorBuilder.agentName ? "auto" : nil,
                    accessoryColor: DS.Color.warning
                ) {
                    onSelect(.agent(a.id))
                }
            }
        }
    }

    private var workflowsCard: some View {
        listCard(
            title: "Workflows", count: counts.workflows, icon: "rectangle.connected.to.line.below",
            tint: DS.Color.purple,
            emptyText: "Workflow'ов нет",
            addLabel: "New workflow"
        ) {
            state.workflowsVM.showNewWorkflowSheet = true
        } content: {
            ForEach(state.workflowsVM.workflows) { wf in
                listRow(
                    icon: "rectangle.connected.to.line.below",
                    iconColor: DS.Color.purple,
                    title: wf.name,
                    subtitle: wf.triggers.isEmpty ? "(no triggers)" : wf.triggersSummary,
                    accessory: nil, accessoryColor: nil
                ) {
                    onSelect(.workflow(wf.id))
                }
            }
        }
    }

    private var schedulesCard: some View {
        listCard(
            title: "Schedules", count: counts.schedules, icon: "calendar",
            tint: DS.Color.success,
            emptyText: "Расписаний нет",
            addLabel: "New schedule"
        ) {
            state.schedulesVM.showNewScheduleSheet = true
        } content: {
            ForEach(state.schedulesVM.scheduler.schedules) { s in
                listRow(
                    icon: scheduleIconName(s),
                    iconColor: s.enabled ? DS.Color.success : DS.Color.textTertiary,
                    title: s.name,
                    subtitle: s.trigger.summary,
                    accessory: s.backend == .cloud ? "cloud" : nil,
                    accessoryColor: DS.Color.purple
                ) {
                    onSelect(.schedule(s.id))
                }
            }
        }
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
                    .help("Создать новый \(title.lowercased())")
                )
            )
            if count == 0 {
                EmptyState(
                    icon: icon,
                    title: emptyText,
                    subtitle: "Создай первый \(title.lowercased()) кнопкой выше",
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

    private func scheduleIconName(_ s: Schedule) -> String {
        switch s.trigger.kind {
        case .cron: return "clock"
        case .once: return "clock.badge.checkmark"
        case .onFiveHourReset: return "arrow.counterclockwise"
        case .onWeeklyReset: return "calendar.badge.exclamationmark"
        }
    }
}
