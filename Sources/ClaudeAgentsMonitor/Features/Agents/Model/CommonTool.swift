import Foundation

enum CommonTool: String, CaseIterable, Identifiable {
    case Read, Edit, Write, Glob, Grep, Bash, WebFetch, WebSearch, TodoWrite, Task

    var id: String { rawValue }
    var description: String {
        switch self {
        case .Read: return "Read files"
        case .Edit: return "Edit files"
        case .Write: return "Write/create files"
        case .Glob: return "Pattern file search"
        case .Grep: return "Content search"
        case .Bash: return "Run shell commands"
        case .WebFetch: return "Fetch URLs"
        case .WebSearch: return "Web search"
        case .TodoWrite: return "Manage tasks"
        case .Task: return "Spawn subagents"
        }
    }
}
