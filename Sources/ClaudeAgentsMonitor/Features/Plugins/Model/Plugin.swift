import Foundation

struct ClaudePlugin: Identifiable, Hashable {
    var id: String { "\(name)@\(marketplace)" }
    let name: String
    let marketplace: String
    let description: String
    let category: String?
    let authorName: String?
    let homepage: String?
    let sourceURL: String?

    /// Is the plugin folder cloned locally?
    let isLocallyAvailable: Bool

    /// Is enabled in user's ~/.claude/settings.json?
    var isEnabled: Bool

    var displayCategory: String { category ?? "general" }
}
