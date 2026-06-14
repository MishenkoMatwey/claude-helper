import Foundation

enum RuleSeverity: String, CaseIterable, Identifiable, Codable {
    case critical
    case major
    case minor

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .major: return 1
        case .minor: return 2
        }
    }
}

struct AgentRule: Identifiable, Hashable, Codable {
    var id: String
    var severity: RuleSeverity
    var category: String
    var title: String
    var pattern: String
    var example: String
    var rationale: String
    var fix: String

    static func empty(id: String = "") -> AgentRule {
        AgentRule(
            id: id,
            severity: .major,
            category: "",
            title: "",
            pattern: "",
            example: "",
            rationale: "",
            fix: ""
        )
    }

    var isFilled: Bool {
        !id.trimmingCharacters(in: .whitespaces).isEmpty
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
