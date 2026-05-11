import Foundation

enum PausedExecutionStore {
    private static var fileURL: URL {
        AgentLoader.agentsDirectory().appendingPathComponent("paused-executions.json")
    }

    static func loadAll() -> [PausedExecution] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PausedExecution].self, from: data)) ?? []
    }

    static func saveAll(_ list: [PausedExecution]) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) {
            try? data.write(to: url)
        }
    }

    static func add(_ execution: PausedExecution) {
        var list = loadAll()
        list.removeAll { $0.id == execution.id }
        list.append(execution)
        saveAll(list)
    }

    static func remove(_ id: String) {
        var list = loadAll()
        list.removeAll { $0.id == id }
        saveAll(list)
    }

    static func update(_ execution: PausedExecution) {
        var list = loadAll()
        if let idx = list.firstIndex(where: { $0.id == execution.id }) {
            list[idx] = execution
        } else {
            list.append(execution)
        }
        saveAll(list)
    }
}
