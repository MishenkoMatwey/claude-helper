import Foundation
import GRDB

/// One unit of agent memory: a fact, rule, playbook, session summary, or variable.
/// Stored in SQLite (`notes` table). Links between notes live in `MemoryEdge`.
struct MemoryNote: Identifiable, Equatable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case fact       // a fact about the project/code
        case rule       // a behavioral rule for the agent
        case playbook   // a reusable procedure
        case session    // a session summary ("what happened last time")
        case variable   // a stored value/var

        // `var` is a Swift keyword, so persist as "var" but expose as `.variable`.
        var rawValue: String {
            switch self {
            case .fact: return "fact"
            case .rule: return "rule"
            case .playbook: return "playbook"
            case .session: return "session"
            case .variable: return "var"
            }
        }

        init?(rawValue: String) {
            switch rawValue {
            case "fact": self = .fact
            case "rule": self = .rule
            case "playbook": self = .playbook
            case "session": self = .session
            case "var": self = .variable
            default: return nil
            }
        }
    }

    enum Status: String, Codable {
        case active
        case archived
    }

    var id: String
    var agent: String          // owning agent name; "" = shared across all agents
    var kind: Kind
    var title: String
    var body: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    var status: Status

    init(
        id: String = MemoryNote.newID(),
        agent: String,
        kind: Kind,
        title: String,
        body: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        status: Status = .active
    ) {
        self.id = id
        self.agent = agent
        self.kind = kind
        self.title = title
        self.body = body
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.status = status
    }

    /// Short, URL-safe, sortable-enough id (`n_` + base36 of random bits).
    static func newID() -> String {
        var value = UInt64.random(in: UInt64.min ... UInt64.max)
        // mix in a second draw for more entropy
        value ^= UInt64.random(in: UInt64.min ... UInt64.max) &* 0x9E3779B97F4A7C15
        return "n_" + String(value, radix: 36)
    }
}

/// A directed, typed link between two notes — the graph edges.
struct MemoryEdge: Equatable, Codable {
    enum Relation: String, Codable, CaseIterable {
        case relates
        case causes
        case supersedes
        case exampleOf = "example_of"
    }

    var src: String
    var dst: String
    var rel: Relation
}

// MARK: - GRDB conformance

extension MemoryNote: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"

    enum Columns {
        static let id = Column("id")
        static let agent = Column("agent")
        static let kind = Column("kind")
        static let title = Column("title")
        static let body = Column("body")
        static let tags = Column("tags")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let lastUsedAt = Column("last_used_at")
        static let useCount = Column("use_count")
        static let status = Column("status")
    }

    init(row: Row) {
        id = row[Columns.id]
        agent = row[Columns.agent]
        kind = Kind(rawValue: row[Columns.kind]) ?? .fact
        title = row[Columns.title]
        body = row[Columns.body]
        let tagsJSON: String = row[Columns.tags] ?? "[]"
        tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
        createdAt = MemoryNote.date(fromMillis: row[Columns.createdAt])
        updatedAt = MemoryNote.date(fromMillis: row[Columns.updatedAt])
        if let ms: Int64 = row[Columns.lastUsedAt] {
            lastUsedAt = MemoryNote.date(fromMillis: ms)
        } else {
            lastUsedAt = nil
        }
        useCount = row[Columns.useCount]
        status = Status(rawValue: row[Columns.status]) ?? .active
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.agent] = agent
        container[Columns.kind] = kind.rawValue
        container[Columns.title] = title
        container[Columns.body] = body
        container[Columns.tags] = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]"
        container[Columns.createdAt] = MemoryNote.millis(from: createdAt)
        container[Columns.updatedAt] = MemoryNote.millis(from: updatedAt)
        container[Columns.lastUsedAt] = lastUsedAt.map(MemoryNote.millis(from:))
        container[Columns.useCount] = useCount
        container[Columns.status] = status.rawValue
    }

    // Epoch-millis <-> Date helpers (matches the RuFlo schema convention).
    static func millis(from date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
    static func date(fromMillis ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
}
