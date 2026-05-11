import Foundation
import SwiftUI

@MainActor
final class TokenUsageViewModel: ObservableObject {
    @Published var summary: TokenSummary = .empty
    @Published var officialUsage: OfficialUsage?
    @Published var officialAccount: OfficialAccount?
    @Published var apiError: String?
    @Published var usageError: String?
    @Published var isRefreshing: Bool = false
    @Published var lastRefresh: Date?

    private let tokenStats: TokenStatsLoader
    private let claudeAPI: ClaudeAPIClient

    var onReset: (PausedExecution.ResumeKind) -> Void = { _ in }

    init(tokenStats: TokenStatsLoader, claudeAPI: ClaudeAPIClient) {
        self.tokenStats = tokenStats
        self.claudeAPI = claudeAPI
    }

    var planLabel: String {
        guard let acc = officialAccount else { return "—" }
        if acc.account.has_claude_max == true { return "Max" }
        if acc.account.has_claude_pro == true { return "Pro" }
        return acc.organization.organization_type?
            .replacingOccurrences(of: "claude_", with: "")
            .capitalized ?? "—"
    }

    var menuBarLabel: String {
        if let usage = officialUsage, let pct = usage.five_hour?.utilization {
            return "\(Int(pct.rounded()))%  •  \(summary.activeSessions.count)⚡"
        }
        return "—  •  \(summary.activeSessions.count)⚡"
    }

    func refresh() async {
        isRefreshing = true
        let newSummary = await Task.detached(priority: .userInitiated) { [tokenStats] in
            tokenStats.loadSummary()
        }.value
        var account: OfficialAccount?
        var usage: OfficialUsage?
        var accountError: String?
        var usageError: String?
        do { account = try await claudeAPI.account() }
        catch { accountError = error.localizedDescription }
        do { usage = try await claudeAPI.usage() }
        catch { usageError = error.localizedDescription }

        if let account { self.officialAccount = account }
        if let usage {
            detectResets(in: usage)
            self.officialUsage = usage
            self.usageError = nil
        } else {
            self.usageError = usageError
        }
        self.summary = newSummary
        self.apiError = (usage == nil && account == nil) ? (usageError ?? accountError) : nil
        self.isRefreshing = false
        self.lastRefresh = Date()
    }

    private func detectResets(in newUsage: OfficialUsage) {
        let prevFive = officialUsage?.five_hour?.resetsAtDate
        let nextFive = newUsage.five_hour?.resetsAtDate
        if let prev = prevFive, let next = nextFive, next > prev.addingTimeInterval(60) {
            onReset(.fiveHour)
        }
        let prevWeek = officialUsage?.seven_day?.resetsAtDate
        let nextWeek = newUsage.seven_day?.resetsAtDate
        if let prev = prevWeek, let next = nextWeek, next > prev.addingTimeInterval(60) {
            onReset(.weekly)
        }
    }
}
