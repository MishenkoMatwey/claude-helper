import Foundation

enum ScheduleBackend: String, Codable, CaseIterable, Identifiable {
    case local
    case cloud
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .local: return "Local (in-app)"
        case .cloud: return "Cloud routine (Anthropic)"
        }
    }
}

enum ScheduleTrigger: Codable, Hashable {
    case cron(expression: String)             // "0 9 * * 1-5"
    case once(at: Date)                        // single run
    case onFiveHourReset                       // when /api/oauth/usage five_hour resets
    case onWeeklyReset                         // when seven_day window resets

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case cron, once, onFiveHourReset, onWeeklyReset
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .cron: return "Cron schedule"
            case .once: return "One-time"
            case .onFiveHourReset: return "When 5-hour limit resets"
            case .onWeeklyReset: return "When weekly limit resets"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .cron: return .cron
        case .once: return .once
        case .onFiveHourReset: return .onFiveHourReset
        case .onWeeklyReset: return .onWeeklyReset
        }
    }

    var summary: String {
        switch self {
        case .cron(let e): return "cron `\(e)`"
        case .once(let d):
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
            return "once at \(f.string(from: d))"
        case .onFiveHourReset: return "on 5-hour reset"
        case .onWeeklyReset: return "on weekly reset"
        }
    }

    enum CodingKeys: String, CodingKey { case kind, expression, at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .cron:
            self = .cron(expression: try c.decode(String.self, forKey: .expression))
        case .once:
            self = .once(at: try c.decode(Date.self, forKey: .at))
        case .onFiveHourReset:
            self = .onFiveHourReset
        case .onWeeklyReset:
            self = .onWeeklyReset
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .cron(let e): try c.encode(e, forKey: .expression)
        case .once(let d): try c.encode(d, forKey: .at)
        case .onFiveHourReset, .onWeeklyReset: break
        }
    }
}

enum ScheduleTarget: Codable, Hashable {
    case agent(name: String)
    case workflow(name: String)

    enum Kind: String, Codable {
        case agent, workflow
    }

    var displayName: String {
        switch self {
        case .agent(let n): return "agent: \(n)"
        case .workflow(let n): return "workflow: \(n)"
        }
    }

    var name: String {
        switch self {
        case .agent(let n), .workflow(let n): return n
        }
    }

    enum CodingKeys: String, CodingKey { case kind, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let name = try c.decode(String.self, forKey: .name)
        self = (kind == .agent) ? .agent(name: name) : .workflow(name: name)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .agent(let n):
            try c.encode(Kind.agent, forKey: .kind)
            try c.encode(n, forKey: .name)
        case .workflow(let n):
            try c.encode(Kind.workflow, forKey: .kind)
            try c.encode(n, forKey: .name)
        }
    }
}

struct Schedule: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String                  // file name slug
    var description: String
    var trigger: ScheduleTrigger
    var target: ScheduleTarget
    var promptMessage: String         // what to send to the agent/orchestrator
    var backend: ScheduleBackend
    var enabled: Bool
    var lastRunAt: Date?
    var nextRunAt: Date?
    var cloudRoutineId: String?       // for cloud backend, ID returned by /schedule
}

struct ScheduleRun: Codable, Identifiable, Hashable {
    var id: String { startedAt.ISO8601Format() }
    let startedAt: Date
    let finishedAt: Date?
    let success: Bool
    let outputTail: String       // last ~600 chars of output
    let tokensIn: Int
    let tokensOut: Int
    let costUSD: Double
}
