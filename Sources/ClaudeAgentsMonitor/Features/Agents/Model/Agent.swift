import Foundation

struct Agent: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let tools: [String]
    let model: String?
    let systemPrompt: String
    let attachedSkills: [String]
    let filePath: URL
    let memoryPath: URL?

    var permissionsSummary: String {
        tools.isEmpty ? "all tools" : tools.joined(separator: ", ")
    }

    /// System prompt without auto-injected blocks (Memory + Variables + Skills).
    var promptWithoutInjectedBlocks: String {
        var s = systemPrompt
        for marker in [
            "\n\n## Memory protocol",
            "\n\n## Variables & Secrets",
            "\n\n## Available skills"
        ] {
            if let range = s.range(of: marker) {
                s = String(s[..<range.lowerBound])
            }
        }
        return s
    }
}
