import Foundation

struct DailyTokens: Identifiable, Hashable {
    var id: String { date }
    let date: String
    let input: Int
    let output: Int
    let cacheCreate: Int
    let cacheRead: Int
    let messages: Int
    let sessions: Int

    var total: Int { input + output + cacheCreate + cacheRead }
}

struct ActiveSession: Identifiable, Hashable {
    let id: String
    let cwd: String
    let startedAt: Date
    let lastActivity: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let model: String?

    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens }
}

struct ModelUsage: Identifiable, Hashable {
    var id: String { model }
    let model: String
    let input: Int
    let output: Int
    let cacheCreate: Int
    let cacheRead: Int
    let messages: Int

    var total: Int { input + output + cacheCreate + cacheRead }
    var family: ModelFamily { ModelFamily.of(model) }
}

enum ModelFamily: String, CaseIterable {
    case opus, sonnet, haiku, other

    static func of(_ raw: String) -> ModelFamily {
        let l = raw.lowercased()
        if l.contains("opus") { return .opus }
        if l.contains("sonnet") { return .sonnet }
        if l.contains("haiku") { return .haiku }
        return .other
    }
}

struct WindowUsage {
    let label: String
    let duration: TimeInterval
    let input: Int
    let output: Int
    let cacheCreate: Int
    let cacheRead: Int
    let messages: Int
    let oldestUsageAt: Date?

    var total: Int { input + output + cacheCreate + cacheRead }

    /// For a rolling window, the next "reset" is when the oldest message exits the window.
    var nextResetAt: Date? {
        guard let oldest = oldestUsageAt else { return nil }
        return oldest.addingTimeInterval(duration)
    }
}

struct TokenSummary {
    var today: DailyTokens?
    var last7Days: [DailyTokens]
    var last30Days: [DailyTokens]
    var activeSessions: [ActiveSession]
    var perModelLast7Days: [ModelUsage]
    var fiveHourWindow: WindowUsage
    var weeklyWindow: WindowUsage

    static let empty = TokenSummary(
        today: nil,
        last7Days: [],
        last30Days: [],
        activeSessions: [],
        perModelLast7Days: [],
        fiveHourWindow: WindowUsage(label: "5h", duration: 5 * 3600, input: 0, output: 0, cacheCreate: 0, cacheRead: 0, messages: 0, oldestUsageAt: nil),
        weeklyWindow: WindowUsage(label: "7d", duration: 7 * 86400, input: 0, output: 0, cacheCreate: 0, cacheRead: 0, messages: 0, oldestUsageAt: nil)
    )
}

// MARK: - Plans

enum PlanTier: String, CaseIterable, Identifiable {
    case pro
    case max5x
    case max20x
    case team
    case enterprise
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pro: return "Pro"
        case .max5x: return "Max 5×"
        case .max20x: return "Max 20×"
        case .team: return "Team"
        case .enterprise: return "Enterprise"
        case .custom: return "Custom"
        }
    }

    /// Approximate token caps per rolling 5-hour window. Anthropic doesn't publish hard
    /// numbers; these are community-observed midpoints used to compute % bars.
    var fiveHourTokenCap: Int {
        switch self {
        case .pro: return 220_000
        case .max5x: return 1_100_000
        case .max20x: return 4_400_000
        case .team: return 1_500_000
        case .enterprise: return 10_000_000
        case .custom: return UserSettings.shared.customFiveHourCap
        }
    }

    var weeklyTokenCap: Int {
        switch self {
        case .pro: return 2_500_000
        case .max5x: return 12_000_000
        case .max20x: return 48_000_000
        case .team: return 18_000_000
        case .enterprise: return 100_000_000
        case .custom: return UserSettings.shared.customWeeklyCap
        }
    }
}

final class UserSettings {
    static let shared = UserSettings()
    private let defaults = UserDefaults.standard
    private let planKey = "planTier"
    private let custom5hKey = "customFiveHourCap"
    private let customWeeklyKey = "customWeeklyCap"

    var plan: PlanTier {
        get { PlanTier(rawValue: defaults.string(forKey: planKey) ?? "") ?? .max5x }
        set { defaults.set(newValue.rawValue, forKey: planKey) }
    }
    var customFiveHourCap: Int {
        get { defaults.integer(forKey: custom5hKey).nonZero ?? 1_000_000 }
        set { defaults.set(newValue, forKey: custom5hKey) }
    }
    var customWeeklyCap: Int {
        get { defaults.integer(forKey: customWeeklyKey).nonZero ?? 10_000_000 }
        set { defaults.set(newValue, forKey: customWeeklyKey) }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
