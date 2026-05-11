import Foundation

protocol PausedExecutionRepository {
    func loadAll() -> [PausedExecution]
    func add(_ execution: PausedExecution)
    func remove(_ id: String)
    func update(_ execution: PausedExecution)
}

struct PausedExecutionRepositoryFile: PausedExecutionRepository {
    func loadAll() -> [PausedExecution] { PausedExecutionStore.loadAll() }
    func add(_ execution: PausedExecution) { PausedExecutionStore.add(execution) }
    func remove(_ id: String) { PausedExecutionStore.remove(id) }
    func update(_ execution: PausedExecution) { PausedExecutionStore.update(execution) }
}
