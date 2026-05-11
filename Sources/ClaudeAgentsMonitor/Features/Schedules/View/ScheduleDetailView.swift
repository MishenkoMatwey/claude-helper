import SwiftUI
import AppKit

struct ScheduleDetailView: View {
    @EnvironmentObject var state: AppState
    let schedule: Schedule

    @State private var runs: [ScheduleRun] = []
    @State private var showDeleteConfirm: Bool = false
    @State private var copied: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metaCard
                if schedule.backend == .cloud {
                    cloudCard
                }
                runsCard
            }
            .padding(20)
        }
        .onAppear(perform: reload)
        .onChange(of: schedule.name) { _, _ in reload() }
        .alert("Delete schedule '\(schedule.name)'?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                state.container.scheduleRepository.delete(schedule)
                state.schedulesVM.scheduler.reload()
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "calendar.circle.fill").font(.largeTitle).foregroundStyle(.tint)
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(schedule.name).font(.title.bold())
                    badge(schedule.backend == .local ? "local" : "cloud",
                          color: schedule.backend == .local ? .blue : .purple)
                    if !schedule.enabled {
                        badge("disabled", color: .secondary)
                    }
                    if state.schedulesVM.scheduler.isFiringNow.contains(schedule.name) {
                        ProgressView().controlSize(.small)
                        Text("running…").font(.caption).foregroundStyle(.blue)
                    }
                }
                if !schedule.description.isEmpty {
                    Text(schedule.description).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(isOn: Binding(
                get: { schedule.enabled },
                set: { state.schedulesVM.scheduler.enable(schedule, $0) }
            )) {
                Text("Enabled").font(.caption)
            }
            .toggleStyle(.switch)

            Button {
                state.schedulesVM.scheduler.runNow(schedule)
            } label: { Label("Run now", systemImage: "play.fill") }
            .buttonStyle(.bordered).tint(.green)

            Button {
                state.schedulesVM.editingSchedule = schedule
            } label: { Label("Edit", systemImage: "pencil") }
            .buttonStyle(.bordered)

            Button {
                showDeleteConfirm = true
            } label: { Label("Delete", systemImage: "trash") }
            .buttonStyle(.bordered).tint(.red)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Trigger", schedule.trigger.summary)
            row("Target", schedule.target.displayName)
            if let next = schedule.nextRunAt {
                row("Next run", "\(next.formatted()) (\(timeUntil(next)))")
            } else if schedule.trigger.kind == .onFiveHourReset || schedule.trigger.kind == .onWeeklyReset {
                let next = (schedule.trigger.kind == .onFiveHourReset
                            ? state.tokensVM.officialUsage?.five_hour?.resetsAtDate
                            : state.tokensVM.officialUsage?.seven_day?.resetsAtDate)
                if let n = next {
                    row("Reset at", "\(n.formatted()) (\(timeUntil(n)))")
                } else {
                    row("Reset at", "unknown — нет данных от API")
                }
            } else {
                row("Next run", "—")
            }
            if let last = schedule.lastRunAt {
                row("Last run", relativeString(last))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt").font(.caption).foregroundStyle(.secondary)
                Text(schedule.promptMessage.isEmpty ? "(empty)" : schedule.promptMessage)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cloud.fill").foregroundStyle(.purple)
                Text("Cloud routine setup").font(.headline)
                Spacer()
            }
            Text("Чтобы создать routine в облаке Anthropic, скопируй команду и вставь в Claude Code сессию (`claude` в терминале):")
                .font(.caption).foregroundStyle(.secondary)
            let cmd = cloudCommand()
            ScrollView {
                Text(cmd)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 140)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(cmd, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy command", systemImage: "doc.on.doc")
                }
                .buttonStyle(PressableButtonStyle())
                if let id = schedule.cloudRoutineId {
                    Spacer()
                    Text("Routine ID: \(id)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .designCard()
    }

    private func cloudCommand() -> String {
        let cron: String = {
            if case .cron(let e) = schedule.trigger { return e }
            return "0 9 * * *"
        }()
        return CloudRoutines.createCommand(
            name: schedule.name,
            cron: cron,
            target: schedule.target.name,
            prompt: schedule.promptMessage
        )
    }

    private var runsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Run history (\(runs.count))").font(.headline)
                Spacer()
                Button("Reload") { reload() }.controlSize(.small)
            }
            if runs.isEmpty {
                Text("Запусков ещё не было.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(runs) { run in
                    runRow(run)
                }
            }
        }
        .designCard()
    }

    private func runRow(_ run: ScheduleRun) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: run.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(run.success ? .green : .red)
                Text(run.startedAt, style: .relative).font(.caption)
                Text("•").foregroundStyle(.secondary)
                if let finished = run.finishedAt {
                    let dur = Int(finished.timeIntervalSince(run.startedAt))
                    Text("\(dur)s").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("in:\(run.tokensIn) out:\(run.tokensOut)")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                if run.costUSD > 0 {
                    Text(String(format: "$%.4f", run.costUSD))
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if !run.outputTail.isEmpty {
                Text(run.outputTail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.callout)
            Spacer()
        }
    }

    private func relativeString(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 0 { return "passed" }
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 24 { return "in \(h / 24)d \(h % 24)h" }
        if h > 0 { return "in \(h)h \(m)m" }
        return "in \(m)m"
    }

    private func reload() {
        runs = state.container.scheduleRepository.loadRuns(for: schedule.name, limit: 30)
    }
}
