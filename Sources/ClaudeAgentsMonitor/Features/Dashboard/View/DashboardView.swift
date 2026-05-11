import SwiftUI
import Charts

enum DetailSelection: Hashable {
    case overview
    case project(String)
    case agent(String)
    case workflow(String)
    case schedule(String)
}

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: DetailSelection? = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch selection {
            case .agent(let id):
                if let agent = state.agentsVM.agents.first(where: { $0.id == id }) {
                    AgentDetailView(agent: agent)
                } else { overview }
            case .workflow(let id):
                if let wf = state.workflowsVM.workflows.first(where: { $0.id == id }) {
                    WorkflowDetailView(workflow: wf)
                } else { overview }
            case .schedule(let id):
                if let s = state.schedulesVM.scheduler.schedules.first(where: { $0.id == id }) {
                    ScheduleDetailView(schedule: s)
                } else { overview }
            case .project(let id):
                if let project = state.projectsVM.allProjects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: project) { sel in
                        selection = sel
                    }
                } else { overview }
            default:
                overview
            }
        }
        .navigationTitle("Claude Agents — \(state.projectsVM.currentProject.name)")
        .toolbar {
            ToolbarItem {
                Button {
                    state.workflowsVM.generateOrchestrator()
                } label: {
                    Image(systemName: "bolt.fill")
                }
                .help("Build orchestrator — пересобрать orchestrator-агента из текущих агентов и workflows")
                .accessibilityLabel("Build orchestrator")
            }
            ToolbarItem {
                Button {
                    state.projectsVM.showPluginsBrowserSheet = true
                } label: {
                    Image(systemName: "puzzlepiece.extension.fill")
                }
                .help("Browse plugins — каталог 177+ Claude Code плагинов с включением одной кнопкой")
                .accessibilityLabel("Browse plugins")
            }
            ToolbarItem {
                Button {
                    state.agentsVM.openAgentsFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open project's .claude/agents/ folder in Finder")
                .accessibilityLabel("Reveal agents folder")
            }
            ToolbarItem {
                SpinningRefreshButton(isRefreshing: state.tokensVM.isRefreshing) {
                    state.refresh()
                }
            }
        }
        .sheet(isPresented: $state.agentsVM.showNewAgentSheet) {
            NewAgentSheet().environmentObject(state)
        }
        .sheet(isPresented: $state.workflowsVM.showNewWorkflowSheet) {
            NewWorkflowSheet().environmentObject(state)
        }
        .sheet(item: $state.workflowsVM.editingWorkflow) { wf in
            NewWorkflowSheet(editing: wf).environmentObject(state)
        }
        .sheet(isPresented: $state.schedulesVM.showNewScheduleSheet) {
            NewScheduleSheet().environmentObject(state)
        }
        .sheet(item: $state.schedulesVM.editingSchedule) { s in
            NewScheduleSheet(editing: s).environmentObject(state)
        }
        .sheet(isPresented: $state.projectsVM.showAddProjectSheet) {
            AddProjectSheet().environmentObject(state)
        }
        .sheet(item: $state.projectsVM.renamingProject) { project in
            RenameProjectSheet(project: project).environmentObject(state)
        }
        .sheet(isPresented: $state.projectsVM.showPluginsBrowserSheet) {
            PluginsBrowserSheet().environmentObject(state)
        }
        .overlay(alignment: .top) {
            if let result = state.workflowsVM.orchestratorBuildResult {
                Text(result)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: state.workflowsVM.orchestratorBuildResult)
        .onChange(of: state.workflowsVM.pendingSelectionWorkflowId) { _, newValue in
            if let id = newValue {
                selection = .workflow(id)
                state.workflowsVM.pendingSelectionWorkflowId = nil
            }
        }
        .onChange(of: state.schedulesVM.pendingSelectionScheduleId) { _, newValue in
            if let id = newValue {
                selection = .schedule(id)
                state.schedulesVM.pendingSelectionScheduleId = nil
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            tokenUsageTile
            Divider()
            projectsList
        }
        .frame(minWidth: 280)
        .background(DS.Color.bg)
    }

    private var tokenUsageTile: some View {
        Button {
            selection = .overview
        } label: {
            HStack(spacing: DS.Space.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .fill(LinearGradient(
                            colors: [DS.Color.accent, DS.Color.purple],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(.white)
                        .font(.system(size: 14, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Token usage").font(DS.Typo.headline)
                    if let pct = state.tokensVM.officialUsage?.five_hour?.utilization {
                        Text("\(Int(pct.rounded()))% used in current 5h window")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    } else {
                        Text("Limits, charts, sessions")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(DS.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m)
                    .fill(selection == .overview ? DS.Color.accent.opacity(0.10) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m)
                            .stroke(selection == .overview ? DS.Color.accent.opacity(0.3) : DS.Color.border, lineWidth: 1)
                    )
            )
            .padding(DS.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Дашборд: лимиты, графики токенов, активные сессии")
    }

    private var projectsList: some View {
        VStack(spacing: 0) {
            HStack {
                sectionHeader("Projects", count: state.projectsVM.allProjects.count, icon: "folder.fill")
                Spacer()
                Button {
                    state.projectsVM.showAddProjectSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(DS.Color.success)
                        .imageScale(.medium)
                }
                .buttonStyle(IconButtonStyle())
                .help("Add a new project (folder picker)")
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(state.projectsVM.allProjects.enumerated()), id: \.element.id) { idx, project in
                        projectRow(project).staggeredAppear(idx)
                    }
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.bottom, DS.Space.l)
            }
        }
    }

    private func projectRow(_ project: ClaudeProject) -> some View {
        let isExpanded = state.projectsVM.expandedProjectId == project.id
        let isCurrent = state.projectsVM.currentProject.id == project.id
        let isSelected = selection == .project(project.id)
        let counts = project.counts
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Chevron — toggles expand only.
                Button {
                    if isExpanded {
                        state.projectsVM.expandedProjectId = nil
                    } else {
                        state.projectsVM.expandedProjectId = project.id
                        if !isCurrent { state.projectsVM.switchProject(project) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Color.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isExpanded)
                        .frame(width: 18, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand to see agents/workflows/schedules")

                // Main button — opens project detail page (and switches project).
                Button {
                    if !isCurrent { state.projectsVM.switchProject(project) }
                    selection = .project(project.id)
                } label: {
                    HStack(spacing: DS.Space.s) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(LinearGradient(
                                    colors: project.isGlobal
                                        ? [DS.Color.accent, DS.Color.purple]
                                        : [DS.Color.success, DS.Color.teal],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 22, height: 22)
                            Image(systemName: project.isGlobal ? "house.fill" : "folder.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Text(project.name).font(DS.Typo.bodyMedium)
                                if isCurrent {
                                    StatusBadge(text: "active", color: DS.Color.success, icon: "circle.fill")
                                }
                            }
                            if !isExpanded {
                                Text("\(counts.agents) agent\(counts.agents == 1 ? "" : "s") · \(counts.workflows) workflow\(counts.workflows == 1 ? "" : "s") · \(counts.schedules) schedule\(counts.schedules == 1 ? "" : "s")")
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.Color.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open project page — \(project.path)")

                projectMenuButton(project)
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.s)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(isSelected ? DS.Color.accent.opacity(0.18)
                          : (isCurrent ? DS.Color.success.opacity(0.08)
                             : (isExpanded ? DS.Color.surfaceElevated : Color.clear)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .stroke(isCurrent ? DS.Color.success.opacity(0.4) : Color.clear, lineWidth: 1)
            )

            if isExpanded {
                projectExpandedContent(project)
                    .padding(.leading, DS.Space.l)
                    .padding(.top, DS.Space.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    private func projectMenuButton(_ project: ClaudeProject) -> some View {
        Menu {
            Button {
                NSWorkspace.shared.open(project.url)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button {
                state.projectsVM.switchProject(project)
            } label: {
                Label("Switch to this project", systemImage: "arrow.right.circle")
            }
            Divider()
            Button {
                state.projectsVM.renamingProject = project
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            .disabled(project.isGlobal)
            Divider()
            Button(role: .destructive) {
                state.projectsVM.removeProject(project)
            } label: {
                Label("Remove from app", systemImage: "trash")
            }
            .disabled(project.isGlobal)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .help(project.isGlobal
              ? "Open / Switch (User project — нельзя переименовать или удалить)"
              : "Open / Rename / Remove project")
    }

    @ViewBuilder
    private func projectExpandedContent(_ project: ClaudeProject) -> some View {
        // Only show interactive nested items if this is the CURRENT project — otherwise we don't have its loaded data.
        if project.id == state.projectsVM.currentProject.id {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                projectSubsection(
                    key: "agents",
                    title: "AGENTS", count: state.agentsVM.userAgents.count, icon: "person.2.fill",
                    addTint: DS.Color.accent,
                    addAction: { state.agentsVM.showNewAgentSheet = true },
                    addHelp: "New agent in \(project.name)"
                ) {
                    ForEach(state.agentsVM.agents) { agent in
                        nestedNavLink(
                            value: DetailSelection.agent(agent.id),
                            content: agentRow(agent)
                        )
                        .contextMenu {
                            agentContextMenu(agent)
                        }
                    }
                }
                projectSubsection(
                    key: "workflows",
                    title: "WORKFLOWS", count: state.workflowsVM.workflows.count, icon: "rectangle.connected.to.line.below",
                    addTint: DS.Color.purple,
                    addAction: { state.workflowsVM.showNewWorkflowSheet = true },
                    addHelp: "New workflow chaining agents"
                ) {
                    ForEach(state.workflowsVM.workflows) { wf in
                        nestedNavLink(
                            value: DetailSelection.workflow(wf.id),
                            content: workflowRow(wf)
                        )
                        .contextMenu {
                            workflowContextMenu(wf)
                        }
                    }
                }
                projectSubsection(
                    key: "schedules",
                    title: "SCHEDULES", count: state.schedulesVM.scheduler.schedules.count, icon: "calendar",
                    addTint: DS.Color.success,
                    addAction: { state.schedulesVM.showNewScheduleSheet = true },
                    addHelp: "Schedule a task"
                ) {
                    ForEach(state.schedulesVM.scheduler.schedules) { s in
                        nestedNavLink(
                            value: DetailSelection.schedule(s.id),
                            content: scheduleRow(s)
                        )
                        .contextMenu {
                            scheduleContextMenu(s)
                        }
                    }
                }
            }
            .padding(.bottom, DS.Space.s)
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text("Switching…")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .padding(.vertical, DS.Space.s)
            .onAppear {
                state.projectsVM.switchProject(project)
            }
        }
    }

    private func projectSubsection<Content: View>(
        key: String,
        title: String, count: Int, icon: String,
        addTint: Color,
        addAction: @escaping () -> Void,
        addHelp: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = state.projectsVM.expandedSubsection[key] ?? true
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    state.projectsVM.expandedSubsection[key] = !isExpanded
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.Color.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isExpanded)
                            .frame(width: 10)
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(title)
                            .font(DS.Typo.micro)
                            .foregroundStyle(DS.Color.textTertiary)
                            .tracking(0.8)
                        Text("\(count)")
                            .font(DS.Typo.micro)
                            .foregroundStyle(DS.Color.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(addTint)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(addTint.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(addTint.opacity(0.30), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(addHelp)
            }
            .padding(.horizontal, DS.Space.s)
            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    @ViewBuilder
    private func agentContextMenu(_ agent: Agent) -> some View {
        Button { selection = .agent(agent.id) } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }
        Button { state.agentsVM.editingAgent = agent } label: {
            Label("Edit settings", systemImage: "pencil")
        }
        Button { state.agentsVM.openAgentInFinder(agent) } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) {
            try? state.container.agentRepository.delete(agent)
            state.refresh()
        } label: {
            Label("Delete agent", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func workflowContextMenu(_ wf: Workflow) -> some View {
        Button { selection = .workflow(wf.id) } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }
        Button { state.workflowsVM.editingWorkflow = wf } label: {
            Label("Edit name / triggers", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            try? state.container.workflowRepository.delete(wf)
            state.refresh()
        } label: {
            Label("Delete workflow", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func scheduleContextMenu(_ s: Schedule) -> some View {
        Button { selection = .schedule(s.id) } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }
        Button { state.schedulesVM.scheduler.runNow(s) } label: {
            Label("Run now", systemImage: "play.fill")
        }
        Button { state.schedulesVM.scheduler.enable(s, !s.enabled) } label: {
            Label(s.enabled ? "Disable" : "Enable",
                  systemImage: s.enabled ? "pause.fill" : "play.fill")
        }
        Button { state.schedulesVM.editingSchedule = s } label: {
            Label("Edit schedule", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            state.container.scheduleRepository.delete(s)
            state.schedulesVM.scheduler.reload()
        } label: {
            Label("Delete schedule", systemImage: "trash")
        }
    }

    private func nestedNavLink<Content: View>(value: DetailSelection, content: Content) -> some View {
        Button {
            selection = value
        } label: {
            content
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .fill(selection == value ? DS.Color.accent.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, count: Int? = nil, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            Text(title.uppercased())
                .font(DS.Typo.micro)
                .foregroundStyle(DS.Color.textTertiary)
                .tracking(0.8)
            if let count {
                Text("\(count)")
                    .font(DS.Typo.micro)
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private func sidebarAddButton(label: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(DS.Typo.bodyMedium)
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.s)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(tint.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.s).stroke(tint.opacity(0.25), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(DS.Typo.caption)
            .foregroundStyle(DS.Color.textTertiary)
            .padding(.vertical, DS.Space.xs)
            .listRowSeparator(.hidden)
    }

    private func workflowRow(_ wf: Workflow) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(wf.name).font(DS.Typo.body)
                if !wf.triggers.isEmpty {
                    Text(wf.triggersSummary)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: "rectangle.connected.to.line.below")
                .foregroundStyle(DS.Color.purple)
        }
    }

    private func scheduleRow(_ s: Schedule) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(s.name)
                        .font(DS.Typo.body)
                        .strikethrough(!s.enabled)
                    if state.schedulesVM.scheduler.isFiringNow.contains(s.name) {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                    if s.backend == .cloud {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Color.purple)
                    }
                }
                Text(s.trigger.summary)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: scheduleIcon(s))
                .foregroundStyle(s.enabled ? DS.Color.success : DS.Color.textTertiary)
        }
    }

    private func scheduleIcon(_ s: Schedule) -> String {
        switch s.trigger.kind {
        case .cron: return "clock"
        case .once: return "clock.badge.checkmark"
        case .onFiveHourReset: return "arrow.counterclockwise"
        case .onWeeklyReset: return "calendar.badge.exclamationmark"
        }
    }

    private func agentRow(_ agent: Agent) -> some View {
        let isOrch = agent.name == OrchestratorBuilder.agentName
        return Label {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(agent.name).font(DS.Typo.body)
                    if isOrch {
                        StatusBadge(text: "auto", color: DS.Color.warning)
                    }
                    Spacer()
                }
                if !agent.description.isEmpty {
                    Text(agent.description)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: isOrch ? "bolt.fill" : "person.crop.circle")
                .foregroundStyle(isOrch ? DS.Color.warning : DS.Color.accent)
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                planRow
                limitsRow
                statsRow
                chartCard
                activeSessionsCard
            }
            .padding(DS.Space.xl)
        }
        .background(DS.Color.bg)
    }

    private var planRow: some View {
        HStack {
            Image(systemName: "creditcard").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Plan usage limits").font(.headline)
                    Text(state.tokensVM.planLabel)
                        .font(.subheadline)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(Capsule())
                }
                if let acc = state.tokensVM.officialAccount {
                    Text("\(acc.account.email ?? "—")  ·  \(acc.organization.name ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let last = state.tokensVM.lastRefresh {
                Label("Last updated: \(last, style: .relative) ago", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var limitsRow: some View {
        if let u = state.tokensVM.officialUsage {
            VStack(spacing: 14) {
                if let b = u.five_hour {
                    officialLimitRow(title: "Current session",
                                     subtitle: "5-hour window",
                                     bucket: b, relativeReset: true)
                }
                if let b = u.seven_day {
                    officialLimitRow(title: "Weekly limit · all models",
                                     subtitle: "7 days",
                                     bucket: b, relativeReset: false)
                }
                if let b = u.seven_day_opus, b.utilization != nil {
                    officialLimitRow(title: "Weekly · Opus",
                                     subtitle: "7 days",
                                     bucket: b, relativeReset: false)
                }
                if let b = u.seven_day_sonnet, b.utilization != nil {
                    officialLimitRow(title: "Weekly · Sonnet",
                                     subtitle: "7 days",
                                     bucket: b, relativeReset: false)
                }
                if let b = u.seven_day_omelette, b.utilization != nil {
                    officialLimitRow(title: "Claude Design",
                                     subtitle: "7 days",
                                     bucket: b, relativeReset: false)
                }
                if let extra = u.extra_usage, extra.is_enabled == true {
                    extraUsageRow(extra)
                }
            }
            .padding(16)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text(state.tokensVM.apiError ?? "Loading limits from claude.com…")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func officialLimitRow(title: String, subtitle: String, bucket: UsageBucket, relativeReset: Bool) -> some View {
        let pct = (bucket.utilization ?? 0) / 100.0
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let reset = bucket.resetsAtDate {
                    Text(relativeReset
                         ? "Resets in \(formatCountdown(to: reset))"
                         : "Resets \(formatResetTime(reset))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.18))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(progressColor(for: pct))
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 10)
            Text("\(Int((bucket.utilization ?? 0).rounded()))% used")
                .font(.system(.callout, design: .monospaced).bold())
                .foregroundStyle(progressColor(for: pct))
                .frame(width: 100, alignment: .trailing)
        }
    }

    private func extraUsageRow(_ extra: ExtraUsage) -> some View {
        HStack {
            Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
            Text("Extra usage").font(.callout)
            Spacer()
            if let used = extra.used_credits, let limit = extra.monthly_limit {
                Text(String(format: "%.2f / %.2f %@", used, limit, extra.currency ?? ""))
                    .font(.system(.callout, design: .monospaced))
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            statCard("Today", formatTokens(state.tokensVM.summary.today.map { $0.input + $0.output + $0.cacheRead + $0.cacheCreate } ?? 0), "tokens", .blue)
            statCard("Last 7d", formatTokens(state.tokensVM.summary.last7Days.reduce(0) { $0 + $1.total }), "tokens", .indigo)
            statCard("Active sessions", "\(state.tokensVM.summary.activeSessions.count)", "now", .green)
            statCard("Agents", "\(state.agentsVM.userAgents.count)", "configured", .orange)
        }
    }

    private func statCard(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(.title, design: .rounded).bold())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("Tokens — last 30 days").font(DS.Typo.title)
                Spacer()
                HStack(spacing: DS.Space.s) {
                    legendDot("output", color: DS.Color.accent)
                    legendDot("input", color: DS.Color.teal)
                }
            }
            Chart(state.tokensVM.summary.last30Days.reversed()) { day in
                BarMark(
                    x: .value("Date", parseDate(day.date) ?? Date(), unit: .day),
                    y: .value("Output", day.output)
                )
                .foregroundStyle(DS.Color.accent.gradient)
                .cornerRadius(2)
                BarMark(
                    x: .value("Date", parseDate(day.date) ?? Date(), unit: .day),
                    y: .value("Input", day.input)
                )
                .foregroundStyle(DS.Color.teal.opacity(0.7).gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(DS.Typo.caption)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(DS.Color.border)
                    AxisValueLabel().font(DS.Typo.caption)
                }
            }
            .frame(height: 240)
        }
        .designCard()
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private var activeSessionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active sessions").font(.headline)
            if state.tokensVM.summary.activeSessions.isEmpty {
                Text("No active sessions in the last 2 hours")
                    .foregroundStyle(.secondary)
            } else {
                Table(state.tokensVM.summary.activeSessions) {
                    TableColumn("Project") { Text(($0.cwd as NSString).lastPathComponent) }
                    TableColumn("Model") { Text($0.model ?? "—") }
                    TableColumn("Last activity") { Text($0.lastActivity, style: .relative) }
                    TableColumn("Input") { Text(formatTokens($0.inputTokens)) }
                    TableColumn("Output") { Text(formatTokens($0.outputTokens)) }
                    TableColumn("Cache read") { Text(formatTokens($0.cacheReadTokens)) }
                }
                .frame(minHeight: 180)
            }
        }
        .designCard()
    }
}
