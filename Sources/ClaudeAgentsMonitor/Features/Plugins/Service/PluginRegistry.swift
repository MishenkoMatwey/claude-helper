import Foundation

enum PluginRegistry {
    private static var marketplacesDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/marketplaces")
    }

    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    static func loadAll() -> [ClaudePlugin] {
        let enabled = loadEnabledPlugins()
        guard let marketplaces = try? FileManager.default.contentsOfDirectory(
            at: marketplacesDir, includingPropertiesForKeys: nil
        ) else { return [] }

        var result: [ClaudePlugin] = []
        for marketplaceDir in marketplaces {
            let marketplaceName = marketplaceDir.lastPathComponent
            let manifestURL = marketplaceDir
                .appendingPathComponent(".claude-plugin/marketplace.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plugins = json["plugins"] as? [[String: Any]]
            else { continue }

            for p in plugins {
                guard let name = p["name"] as? String else { continue }
                let id = "\(name)@\(marketplaceName)"
                let description = (p["description"] as? String) ?? ""
                let category = p["category"] as? String
                let author = (p["author"] as? [String: Any])?["name"] as? String
                let homepage = p["homepage"] as? String
                let sourceURL = (p["source"] as? [String: Any])?["url"] as? String

                let local1 = marketplaceDir.appendingPathComponent("plugins/\(name)")
                let local2 = marketplaceDir.appendingPathComponent("external_plugins/\(name)")
                let isLocal = FileManager.default.fileExists(atPath: local1.path)
                    || FileManager.default.fileExists(atPath: local2.path)

                result.append(ClaudePlugin(
                    name: name, marketplace: marketplaceName,
                    description: description, category: category,
                    authorName: author, homepage: homepage, sourceURL: sourceURL,
                    isLocallyAvailable: isLocal, isEnabled: enabled[id] == true
                ))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    static func setEnabled(_ plugin: ClaudePlugin, _ enabled: Bool) throws {
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = dict
        }
        var plugins = (settings["enabledPlugins"] as? [String: Bool]) ?? [:]
        if enabled { plugins[plugin.id] = true }
        else { plugins.removeValue(forKey: plugin.id) }
        settings["enabledPlugins"] = plugins
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL)
    }

    static func categories(in plugins: [ClaudePlugin]) -> [String] {
        Array(Set(plugins.map(\.displayCategory))).sorted()
    }

    private static func loadEnabledPlugins() -> [String: Bool] {
        guard let data = try? Data(contentsOf: settingsURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return (dict["enabledPlugins"] as? [String: Bool]) ?? [:]
    }
}
