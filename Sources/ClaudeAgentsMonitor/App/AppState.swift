import Foundation
import SwiftUI
import Combine

/// Thin coordinator that owns feature view models and orchestrates cross-feature concerns.
/// Views inject `@EnvironmentObject var state: AppState` and access feature state via
/// `state.projects.X`, `state.agents.Y`, etc.
@MainActor
final class AppState: ObservableObject {
    let container: AppContainer
    var projectsVM: ProjectsViewModel
    var agentsVM: AgentsViewModel
    var workflowsVM: WorkflowsViewModel
    var schedulesVM: SchedulesViewModel
    var tokensVM: TokenUsageViewModel

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer = AppContainer()) {
        self.container = container

        // Construct feature view models with their dependencies.
        // ProjectsViewModel needs an onSwitch callback — set as a holder we fill below.
        var refreshHolder: (() -> Void) = {}
        let projectsVM = ProjectsViewModel(
            repository: container.projectRepository,
            onSwitch: { refreshHolder() }
        )
        let agentsVM = AgentsViewModel(
            agentRepository: container.agentRepository,
            skillRepository: container.skillRepository,
            mcpRepository: container.mcpRepository
        )
        let workflowsVM = WorkflowsViewModel(workflowRepository: container.workflowRepository)
        let schedulesVM = SchedulesViewModel()
        let tokensVM = TokenUsageViewModel(
            tokenStats: container.tokenStats,
            claudeAPI: container.claudeAPI
        )

        self.projectsVM = projectsVM
        self.agentsVM = agentsVM
        self.workflowsVM = workflowsVM
        self.schedulesVM = schedulesVM
        self.tokensVM = tokensVM

        // Wire scheduler so it can resolve the renamed orchestrator name when
        // a schedule targets a workflow.
        schedulesVM.scheduler.agentsProvider = { [weak agentsVM] in agentsVM?.agents ?? [] }

        // Forward feature changes upward so views observing AppState repaint.
        let upward: () -> Void = { [weak self] in self?.objectWillChange.send() }
        projectsVM.objectWillChange.sink { _ in upward() }.store(in: &cancellables)
        agentsVM.objectWillChange.sink { _ in upward() }.store(in: &cancellables)
        workflowsVM.objectWillChange.sink { _ in upward() }.store(in: &cancellables)
        schedulesVM.objectWillChange.sink { _ in upward() }.store(in: &cancellables)
        tokensVM.objectWillChange.sink { _ in upward() }.store(in: &cancellables)

        tokensVM.onReset = { [weak self] kind in
            guard let self else { return }
            Task {
                switch kind {
                case .fiveHour:
                    await self.schedulesVM.scheduler.notifyFiveHourReset()
                    await ExecutionResumer.resumeAll(matching: .fiveHour)
                case .weekly:
                    await self.schedulesVM.scheduler.notifyWeeklyReset()
                    await ExecutionResumer.resumeAll(matching: .weekly)
                }
            }
        }

        refreshHolder = { [weak self] in self?.refresh() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Refresh agents, workflows, scheduler, and tokens (API + summary).
    func refresh() {
        agentsVM.reload()
        workflowsVM.reload()
        schedulesVM.scheduler.reload()
        Task { await tokensVM.refresh() }
    }
}
