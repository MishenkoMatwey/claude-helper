import Foundation

protocol AgentVariablesRepository {
    func loadAll(for agentName: String) -> [AgentVariable]
    func save(key: String, value: String, isSecret: Bool, for agentName: String) throws
    func delete(key: String, for agentName: String)
    func revealSecret(key: String, for agentName: String) -> String?
    func keychainService(for agentName: String) -> String
}

struct AgentVariablesRepositoryKeychain: AgentVariablesRepository {
    func loadAll(for agentName: String) -> [AgentVariable] { AgentVariablesService.loadAll(for: agentName) }
    func save(key: String, value: String, isSecret: Bool, for agentName: String) throws {
        try AgentVariablesService.save(key: key, value: value, isSecret: isSecret, for: agentName)
    }
    func delete(key: String, for agentName: String) { AgentVariablesService.delete(key: key, for: agentName) }
    func revealSecret(key: String, for agentName: String) -> String? {
        AgentVariablesService.revealSecret(key: key, for: agentName)
    }
    func keychainService(for agentName: String) -> String { AgentVariablesService.keychainService(for: agentName) }
}
