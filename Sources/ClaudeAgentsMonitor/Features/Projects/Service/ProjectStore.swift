import Foundation

enum ProjectStore {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/agents-monitor/projects.json")
    }

    static func loadAll() -> [ClaudeProject] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ClaudeProject].self, from: data)
        else { return [] }
        return list
    }

    static func saveAll(_ list: [ClaudeProject]) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(list) {
            try? data.write(to: url)
        }
    }

    static func add(_ project: ClaudeProject) {
        var list = loadAll()
        if list.contains(where: { $0.path == project.path }) { return }
        list.append(project)
        saveAll(list)
    }

    static func remove(_ project: ClaudeProject) {
        var list = loadAll()
        list.removeAll { $0.path == project.path }
        saveAll(list)
    }

    static func rename(_ project: ClaudeProject, to newName: String) {
        var list = loadAll()
        if let idx = list.firstIndex(where: { $0.path == project.path }) {
            list[idx] = ClaudeProject(name: newName, path: project.path, isGlobal: project.isGlobal)
            saveAll(list)
        }
    }
}
