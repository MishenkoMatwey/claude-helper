import SwiftUI

struct RunWorkflowSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let workflow: Workflow

    @StateObject private var runner = WorkflowRunner()
    @State private var trigger: String = ""
    @State private var autoResume: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            transcript
            Divider()
            footer
        }
        .frame(width: 820, height: 700)
        .onAppear {
            if trigger.isEmpty { trigger = workflow.triggers.first ?? workflow.description }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .foregroundStyle(.tint).font(.title)
            VStack(alignment: .leading, spacing: 0) {
                Text("Run workflow — \(workflow.name)").font(.title2.bold())
                Text("Запускает orchestrator-агента c триггер-сообщением. Реальные токены из твоей квоты.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { runner.cancel(); dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trigger message").font(.callout.weight(.semibold))
                Spacer()
                if !workflow.triggers.isEmpty {
                    Menu {
                        ForEach(workflow.triggers, id: \.self) { t in
                            Button(t) { trigger = t }
                        }
                    } label: {
                        Label("Use saved trigger…", systemImage: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 180)
                }
            }
            TextField("То, что бы ты написал юзером для активации workflow", text: $trigger)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    runner.run(
                        workflow: workflow,
                        agentName: OrchestratorBuilder.agentName,
                        trigger: trigger,
                        autoResume: autoResume,
                        fiveHourResetAt: state.tokensVM.officialUsage?.five_hour?.resetsAtDate,
                        weeklyResetAt: state.tokensVM.officialUsage?.seven_day?.resetsAtDate
                    )
                } label: {
                    if runner.status == .running {
                        HStack { ProgressView().controlSize(.small); Text("Running…") }
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(runner.status == .running || trigger.trimmingCharacters(in: .whitespaces).isEmpty)
                if runner.status == .running {
                    Button("Stop") { runner.cancel() }
                        .buttonStyle(.bordered).tint(.red)
                }
                Toggle(isOn: $autoResume) {
                    Label("Auto-resume on rate limit", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .help("Если задача упадёт по 5h/weekly лимиту — автоматически продолжить когда лимит сбросится")
                Spacer()
                statusBadge
            }
            if runner.status == .rateLimited, let reset = runner.rateLimitedReset {
                pausedBanner(reset: reset)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func pausedBanner(reset: Date) -> some View {
        HStack {
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Paused — rate limit reached").font(.callout.bold())
                Text(autoResume
                     ? "Auto-resume registered. Will continue when limit resets at \(reset, style: .time)."
                     : "Auto-resume off — задача не возобновится автоматически.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let session = runner.sessionId {
                Text("session: \(String(session.prefix(8)))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            switch runner.status {
            case .idle:
                Text("idle").font(.caption).foregroundStyle(.secondary)
            case .running:
                Image(systemName: "circle.fill").foregroundStyle(.blue).imageScale(.small)
                Text(String(format: "running %.0fs", runner.elapsedSeconds))
                    .font(.system(.caption, design: .monospaced))
            case .finished(let success):
                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(success ? .green : .red)
                Text(String(format: "%@ in %.0fs", success ? "done" : "failed", runner.elapsedSeconds))
                    .font(.system(.caption, design: .monospaced))
            case .rateLimited:
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                Text("rate-limited").font(.system(.caption, design: .monospaced)).foregroundStyle(.orange)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(runner.lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                    if runner.lines.isEmpty {
                        Text("Output появится здесь, когда запустишь.")
                            .font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: runner.lines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("[error]") || line.hasPrefix("[stderr]") || line.hasPrefix("[exit") { return .red }
        if line.hasPrefix("▶") { return .blue }
        if line.hasPrefix("→") { return .purple }
        if line.hasPrefix("  ✓") { return .green }
        if line.hasPrefix("■") { return .orange }
        return .primary
    }

    private var footer: some View {
        HStack {
            Text("Транскрипт идёт через `claude --agent orchestrator --print --output-format stream-json`. Это полноценный запуск, не симуляция.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Close") { runner.cancel(); dismiss() }
        }
        .padding(20)
    }
}
