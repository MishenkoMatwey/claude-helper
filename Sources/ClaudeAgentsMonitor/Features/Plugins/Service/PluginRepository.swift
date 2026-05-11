import Foundation

protocol PluginRepository {
    func loadAll() -> [ClaudePlugin]
    func setEnabled(_ plugin: ClaudePlugin, _ enabled: Bool) throws
    func categories(in plugins: [ClaudePlugin]) -> [String]
}

struct PluginRepositoryFile: PluginRepository {
    func loadAll() -> [ClaudePlugin] { PluginRegistry.loadAll() }
    func setEnabled(_ plugin: ClaudePlugin, _ enabled: Bool) throws {
        try PluginRegistry.setEnabled(plugin, enabled)
    }
    func categories(in plugins: [ClaudePlugin]) -> [String] {
        PluginRegistry.categories(in: plugins)
    }
}
