import Foundation

protocol ProjectRepository {
    func loadAll() -> [ClaudeProject]
    func add(_ project: ClaudeProject)
    func remove(_ project: ClaudeProject)
    func rename(_ project: ClaudeProject, to newName: String)
}

struct ProjectRepositoryFile: ProjectRepository {
    func loadAll() -> [ClaudeProject] { ProjectStore.loadAll() }
    func add(_ project: ClaudeProject) { ProjectStore.add(project) }
    func remove(_ project: ClaudeProject) { ProjectStore.remove(project) }
    func rename(_ project: ClaudeProject, to newName: String) {
        ProjectStore.rename(project, to: newName)
    }
}
