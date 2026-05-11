import Foundation

protocol MCPRepository {
    func loadAvailable(currentProjectPath: String?) -> [MCPServer]
}

struct MCPRepositoryFile: MCPRepository {
    func loadAvailable(currentProjectPath: String?) -> [MCPServer] {
        MCPRegistry.loadAvailable(currentProjectPath: currentProjectPath)
    }
}
