import Foundation

/// Single source of truth for all service dependencies.
/// Views receive feature ViewModels which receive these protocols — no static state.
final class AppContainer {
    // Live (file-system / network) instances — replaceable in tests with mocks.

    let agentRepository: AgentRepository
    let agentVariables: AgentVariablesRepository
    let workflowRepository: WorkflowRepository
    let scheduleRepository: ScheduleRepository
    let projectRepository: ProjectRepository
    let pluginRepository: PluginRepository
    let skillRepository: SkillRepository
    let mcpRepository: MCPRepository

    let claudeAPI: ClaudeAPIClient
    let notifications: NotificationsClient
    let tokenStats: TokenStatsLoader
    let orchestrator: OrchestratorBuilding
    let permissions: PermissionsService
    let pausedExecutions: PausedExecutionRepository

    init() {
        let agentRepo = AgentRepositoryFile()
        self.agentRepository = agentRepo
        self.agentVariables = AgentVariablesRepositoryKeychain()
        self.workflowRepository = WorkflowRepositoryFile()
        self.scheduleRepository = ScheduleRepositoryFile()
        self.projectRepository = ProjectRepositoryFile()
        self.pluginRepository = PluginRepositoryFile()
        self.skillRepository = SkillRepositoryFile()
        self.mcpRepository = MCPRepositoryFile()

        self.claudeAPI = ClaudeAPIClientLive()
        self.notifications = NotificationsClientLive()
        self.tokenStats = TokenStatsLoaderFile()
        self.orchestrator = OrchestratorBuilderLive()
        self.permissions = PermissionsServiceLive()
        self.pausedExecutions = PausedExecutionRepositoryFile()
    }
}
