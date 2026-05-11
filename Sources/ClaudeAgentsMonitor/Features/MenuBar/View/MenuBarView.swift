import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            header
            if let err = state.tokensVM.apiError { errorBanner(err) }
            limitsCard
            activeSessionsCard
            footer
        }
        .padding(DS.Space.m)
        .frame(width: 380)
        .background(DS.Color.bg)
        .transaction { $0.animation = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(LinearGradient(
                        colors: [DS.Color.accent, DS.Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Claude Agents")
                    .font(DS.Typo.headline)
                if let acc = state.tokensVM.officialAccount {
                    HStack(spacing: 4) {
                        Text(acc.account.display_name ?? "—")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                        Text("·").foregroundStyle(DS.Color.textTertiary)
                        StatusBadge(text: state.tokensVM.planLabel, color: DS.Color.accent)
                    }
                }
            }
            Spacer()
            SpinningRefreshButton(isRefreshing: state.tokensVM.isRefreshing) {
                state.refresh()
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Color.warning)
            Text(message)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer()
        }
        .padding(DS.Space.s)
        .background(DS.Color.warning.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.s).stroke(DS.Color.warning.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
    }

    // MARK: Limits

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            DesignSectionHeader(
                title: "Plan usage limits",
                subtitle: state.tokensVM.planLabel,
                icon: "chart.bar.fill"
            )
            if let u = state.tokensVM.officialUsage {
                if let bucket = u.five_hour {
                    limitRow(title: "Current session", subtitle: "5-hour window",
                             utilization: bucket.utilization, resetsAt: bucket.resetsAtDate, relative: true)
                }
                if let bucket = u.seven_day {
                    limitRow(title: "Weekly · all models", subtitle: "7 days",
                             utilization: bucket.utilization, resetsAt: bucket.resetsAtDate, relative: false)
                }
                if let bucket = u.seven_day_opus, bucket.utilization != nil {
                    limitRow(title: "Weekly · Opus", subtitle: "7 days",
                             utilization: bucket.utilization, resetsAt: bucket.resetsAtDate, relative: false)
                }
                if let bucket = u.seven_day_sonnet, bucket.utilization != nil {
                    limitRow(title: "Weekly · Sonnet only", subtitle: "7 days",
                             utilization: bucket.utilization, resetsAt: bucket.resetsAtDate, relative: false)
                }
                if let bucket = u.seven_day_omelette, bucket.utilization != nil {
                    limitRow(title: "Claude Design", subtitle: "7 days",
                             utilization: bucket.utilization, resetsAt: bucket.resetsAtDate, relative: false)
                }
                if let extra = u.extra_usage, extra.is_enabled == true {
                    extraUsageRow(extra)
                }
            } else if let err = state.tokensVM.usageError {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DS.Color.warning)
                        Text("Couldn't load usage")
                            .font(DS.Typo.caption).foregroundStyle(DS.Color.warning)
                    }
                    Text(err).font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(2)
                    Button("Retry") { state.refresh() }
                        .buttonStyle(GhostButtonStyle())
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Skeleton(height: 14, width: 120)
                    Skeleton(height: 8)
                    Skeleton(height: 14, width: 150)
                    Skeleton(height: 8)
                }
            }
            sparklineRow
        }
        .designCard()
    }

    private var sparklineRow: some View {
        let values = state.tokensVM.summary.last30Days.suffix(14).map { Double($0.input + $0.output) }
        return Group {
            if values.contains(where: { $0 > 0 }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last 14 days")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        let total = values.reduce(0, +)
                        Text(formatTokens(Int(total)))
                            .font(DS.Typo.monoSmall)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    Sparkline(values: values, color: DS.Color.accent)
                        .frame(height: 28)
                }
            }
        }
    }

    private func limitRow(title: String, subtitle: String, utilization: Double?, resetsAt: Date?, relative: Bool) -> some View {
        let pct = (utilization ?? 0) / 100.0
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Text(title).font(DS.Typo.bodyMedium)
                Spacer()
                Text("\(Int((utilization ?? 0).rounded()))%")
                    .font(DS.Typo.monoBold)
                    .foregroundStyle(DS.Color.semantic(forUtilization: pct))
            }
            DesignProgressBar(value: pct, height: 7)
            if let reset = resetsAt {
                Text(relative
                     ? "Resets in \(formatCountdown(to: reset))"
                     : "Resets \(formatResetTime(reset))")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    private func extraUsageRow(_ extra: ExtraUsage) -> some View {
        HStack {
            Image(systemName: "plus.circle.fill").foregroundStyle(DS.Color.accent)
            Text("Extra usage").font(DS.Typo.caption)
            Spacer()
            if let used = extra.used_credits, let limit = extra.monthly_limit {
                Text(String(format: "%.2f / %.2f %@", used, limit, extra.currency ?? ""))
                    .font(DS.Typo.monoSmall).foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    // MARK: Active sessions

    private var activeSessionsCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Active sessions",
                subtitle: "Last 2 hours",
                icon: "bolt.fill"
            )
            if state.tokensVM.summary.activeSessions.isEmpty {
                Text("None active")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            } else {
                ForEach(state.tokensVM.summary.activeSessions.prefix(3)) { session in
                    HStack {
                        Circle().fill(DS.Color.success).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((session.cwd as NSString).lastPathComponent)
                                .font(DS.Typo.monoSmall).lineLimit(1)
                            Text(session.model.map(prettyModel) ?? "—")
                                .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                        }
                        Spacer()
                        Text(formatTokens(session.totalTokens))
                            .font(DS.Typo.monoSmall).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
        }
        .designCard()
    }

    // MARK: Agents

    private var agentsCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DesignSectionHeader(
                title: "Agents",
                subtitle: "\(state.agentsVM.userAgents.count) configured",
                icon: "person.2.fill",
                trailing: AnyView(
                    Button {
                        openDashboard()
                        state.agentsVM.showNewAgentSheet = true
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(IconButtonStyle())
                        .help("New agent")
                )
            )
            if state.agentsVM.agents.isEmpty {
                Button("Create your first agent…") {
                    openDashboard()
                    state.agentsVM.showNewAgentSheet = true
                }
                .buttonStyle(GhostButtonStyle())
            } else {
                ForEach(state.agentsVM.agents.prefix(4)) { agent in
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(DS.Color.accent)
                        Text(agent.name).font(DS.Typo.body)
                        Spacer()
                        Text(agent.model ?? "default")
                            .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
        }
        .designCard()
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                openDashboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.grid.2x2.fill").imageScale(.small)
                    Text("Open Dashboard")
                }
            }
            .buttonStyle(PressableButtonStyle())
            Spacer()
            if let last = state.tokensVM.lastRefresh {
                Text("Updated \(last, style: .relative) ago")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(OutlineButtonStyle())
                .keyboardShortcut("q")
        }
    }

    private func openDashboard() {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}

func prettyModel(_ raw: String) -> String {
    raw.replacingOccurrences(of: "claude-", with: "")
        .replacingOccurrences(of: "-2024", with: "")
        .replacingOccurrences(of: "-2025", with: "")
        .replacingOccurrences(of: "-2026", with: "")
}
