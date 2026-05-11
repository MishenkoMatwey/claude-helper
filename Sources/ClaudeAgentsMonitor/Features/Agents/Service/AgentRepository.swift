import Foundation

/// Domain interface for agent CRUD. Lets ViewModels work without depending on file system directly.
protocol AgentRepository {
    func loadAll() -> [Agent]
    func save(name: String, description: String, model: String, tools: [String],
              systemPrompt: String, skills: [Skill], overwrite: Bool) throws -> URL
    func delete(_ agent: Agent) throws
    func agentsDirectory() -> URL
    func memoryProtocolBlock(agentName: String) -> String
    func variablesBlock(agentName: String) -> String
}

struct AgentRepositoryFile: AgentRepository {
    func loadAll() -> [Agent] { AgentLoader.loadAll() }
    func save(name: String, description: String, model: String, tools: [String],
              systemPrompt: String, skills: [Skill], overwrite: Bool) throws -> URL {
        try AgentWriter.save(name: name, description: description, model: model,
                             tools: tools, systemPrompt: systemPrompt,
                             skills: skills, overwrite: overwrite)
    }
    func delete(_ agent: Agent) throws { try AgentWriter.delete(agent) }
    func agentsDirectory() -> URL { AgentLoader.agentsDirectory() }
    func memoryProtocolBlock(agentName: String) -> String { AgentWriter.memoryProtocolBlock(agentName: agentName) }
    func variablesBlock(agentName: String) -> String { AgentWriter.variablesBlock(agentName: agentName) }
}
