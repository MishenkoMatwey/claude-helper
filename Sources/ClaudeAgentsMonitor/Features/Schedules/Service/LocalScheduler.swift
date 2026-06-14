import Foundation
import Combine

@MainActor
final class LocalScheduler: ObservableObject {
    @Published private(set) var schedules: [Schedule] = []
    @Published private(set) var isFiringNow: Set<String> = []   // schedule names being executed

    private var timer: Timer?
    private var lastFiveHourReset: Date?
    private var lastWeeklyReset: Date?

    /// Closure that returns the current agent list — used to resolve the orchestrator's
    /// actual file name when a schedule targets a workflow. Set from the app container.
    var agentsProvider: (() -> [Agent])?

    init() {
        reload()
        // Tick every 30 seconds.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    func reload() {
        schedules = ScheduleStore.loadAll()
        recomputeNextRuns()
    }

    func enable(_ schedule: Schedule, _ enabled: Bool) {
        var s = schedule
        s.enabled = enabled
        try? ScheduleStore.save(s, overwrite: true)
        reload()
    }

    func runNow(_ schedule: Schedule) {
        Task { await execute(schedule, manual: true) }
    }

    private func recomputeNextRuns() {
        let now = Date()
        for i in schedules.indices where schedules[i].enabled {
            schedules[i].nextRunAt = nextRunDate(for: schedules[i], from: now)
        }
    }

    private func nextRunDate(for s: Schedule, from now: Date) -> Date? {
        switch s.trigger {
        case .cron(let expr):
            return CronExpression(expr)?.nextDate(after: now)
        case .once(let date):
            return date > now ? date : nil
        case .onFiveHourReset, .onWeeklyReset:
            return nil  // unknown; reacts to event, not schedule
        }
    }

    private func tick() async {
        let now = Date()
        // Update reset trackers if API data available; we'll get notified by AppState.
        for s in schedules where s.enabled {
            if shouldFire(s, at: now) {
                await execute(s, manual: false)
            }
        }
        recomputeNextRuns()
    }

    private func shouldFire(_ s: Schedule, at now: Date) -> Bool {
        // Avoid double-fire (60s tolerance).
        if let last = s.lastRunAt, now.timeIntervalSince(last) < 90 { return false }
        switch s.trigger {
        case .cron(let expr):
            guard let cron = CronExpression(expr) else { return false }
            return cron.matches(now)
        case .once(let target):
            return now >= target && (s.lastRunAt == nil)
        case .onFiveHourReset, .onWeeklyReset:
            return false  // triggered explicitly via notifyResetHappened()
        }
    }

    /// Called by AppState when it observes a usage reset.
    func notifyFiveHourReset() async {
        for s in schedules where s.enabled && s.trigger.kind == .onFiveHourReset {
            await execute(s, manual: false)
        }
    }

    func notifyWeeklyReset() async {
        for s in schedules where s.enabled && s.trigger.kind == .onWeeklyReset {
            await execute(s, manual: false)
        }
    }

    // MARK: - Execution

    private func execute(_ schedule: Schedule, manual: Bool) async {
        guard !isFiringNow.contains(schedule.name) else { return }
        isFiringNow.insert(schedule.name)
        defer {
            Task { @MainActor in
                self.isFiringNow.remove(schedule.name)
            }
        }

        let startedAt = Date()
        var success = false
        var output = ""
        var tokensIn = 0
        var tokensOut = 0
        var costUSD = 0.0

        if schedule.backend == .cloud {
            // Cloud backend: handled separately via CloudRoutinesService.
            // For local schedule object marked cloud, we just log a "skipped" run here.
            output = "Cloud routine — Anthropic will execute it on their side."
            success = true
        } else {
            let result = await ClaudeRunner.run(
                agentName: targetAgentName(for: schedule),
                prompt: schedule.promptMessage
            )
            success = result.success
            output = result.tail
            tokensIn = result.tokensIn
            tokensOut = result.tokensOut
            costUSD = result.costUSD
        }

        let run = ScheduleRun(
            startedAt: startedAt,
            finishedAt: Date(),
            success: success,
            outputTail: output,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            costUSD: costUSD
        )
        ScheduleStore.appendRun(run, scheduleName: schedule.name)

        // Update lastRunAt
        if let idx = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[idx].lastRunAt = Date()
            try? ScheduleStore.save(schedules[idx], overwrite: true)
        }

        if !manual {
            if success {
                NotificationService.notifyScheduleSucceeded(name: schedule.name)
            } else {
                NotificationService.notifyScheduleFailed(name: schedule.name)
            }
        }
    }

    private func targetAgentName(for schedule: Schedule) -> String {
        switch schedule.target {
        case .agent(let n): return n
        case .workflow:
            // Prefer the user's actual orchestrator (renamed via role: orchestrator).
            if let orch = agentsProvider?().activeOrchestrator() {
                return orch.name
            }
            return OrchestratorBuilder.agentName
        }
    }
}

// MARK: - Headless claude runner

enum ClaudeRunner {
    struct Result {
        let success: Bool
        let tail: String
        let tokensIn: Int
        let tokensOut: Int
        let costUSD: Double
    }

    static func run(agentName: String, prompt: String) async -> Result {
        guard let cli = locateCLI() else {
            return Result(success: false, tail: "[claude CLI not found]", tokensIn: 0, tokensOut: 0, costUSD: 0)
        }

        let process = Process()
        process.executableURL = cli
        process.arguments = [
            "--agent", agentName,
            "--print",
            "--output-format", "json",
            prompt
        ]
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(success: false, tail: "[spawn failed: \(error.localizedDescription)]",
                          tokensIn: 0, tokensOut: 0, costUSD: 0)
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<Result, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                let combined = (outStr + (errStr.isEmpty ? "" : "\n[stderr]\n" + errStr))
                let tail = String(combined.suffix(800))

                var tokensIn = 0, tokensOut = 0, cost = 0.0
                if let data = outStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let usage = obj["usage"] as? [String: Any] {
                        tokensIn = (usage["input_tokens"] as? Int) ?? 0
                        tokensOut = (usage["output_tokens"] as? Int) ?? 0
                    }
                    cost = (obj["total_cost_usd"] as? Double) ?? 0
                }
                cont.resume(returning: Result(
                    success: process.terminationStatus == 0,
                    tail: tail,
                    tokensIn: tokensIn,
                    tokensOut: tokensOut,
                    costUSD: cost
                ))
            }
        }
    }

    private static func locateCLI() -> URL? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
