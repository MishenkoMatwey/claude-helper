import Foundation
import SwiftUI
import AppKit

@MainActor
final class AgentsViewModel: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var availableSkills: [Skill] = []
    @Published var availableMCPServers: [MCPServer] = []
    @Published var showNewAgentSheet: Bool = false
    @Published var editingAgent: Agent?

    private let agentRepository: AgentRepository
    private let skillRepository: SkillRepository
    private let mcpRepository: MCPRepository

    init(agentRepository: AgentRepository,
         skillRepository: SkillRepository,
         mcpRepository: MCPRepository) {
        self.agentRepository = agentRepository
        self.skillRepository = skillRepository
        self.mcpRepository = mcpRepository
    }

    var userAgents: [Agent] {
        agents.filter { $0.name != OrchestratorBuilder.agentName }
    }

    func reload() {
        agents = agentRepository.loadAll()
        availableSkills = skillRepository.loadAll()
        availableMCPServers = mcpRepository.loadAvailable(currentProjectPath: nil)
    }

    func openAgentInFinder(_ agent: Agent) {
        NSWorkspace.shared.activateFileViewerSelecting([agent.filePath])
    }

    func openAgentsFolder() {
        let url = agentRepository.agentsDirectory()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
