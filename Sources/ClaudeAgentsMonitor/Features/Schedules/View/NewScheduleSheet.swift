import SwiftUI
import AppKit

struct NewScheduleSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let editing: Schedule?

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var triggerKind: ScheduleTrigger.Kind = .cron
    @State private var cronExpr: String = "0 9 * * 1-5"
    @State private var onceAt: Date = Date().addingTimeInterval(3600)
    @State private var targetKind: TargetKind = .agent
    @State private var targetName: String = ""
    @State private var promptMessage: String = ""
    @State private var backend: ScheduleBackend = .local
    @State private var enabled: Bool = true
    @State private var error: String?
    @State private var didLoad: Bool = false

    enum TargetKind: String, CaseIterable, Identifiable {
        case agent, workflow
        var id: String { rawValue }
    }

    init(editing: Schedule? = nil) {
        self.editing = editing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameRow
                    descriptionRow
                    triggerRow
                    targetRow
                    promptRow
                    backendRow
                    enabledRow
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 720)
        .onAppear { loadIfNeeded() }
    }

    private var header: some View {
        HStack {
            Image(systemName: editing == nil ? "calendar.badge.plus" : "calendar.badge.checkmark")
                .foregroundStyle(.tint).font(.title)
            Text(editing == nil ? "New schedule" : "Edit — \(editing!.name)").font(.title2.bold())
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle()).keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Name", "Lowercase, digits, hyphen")
            TextField("e.g. daily-jira-summary, resume-on-reset", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(editing != nil)
        }
    }

    private var descriptionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Description", "Зачем этот schedule")
            TextField("Short purpose", text: $description, axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var triggerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Trigger", "Когда запускать")
            Picker("", selection: $triggerKind) {
                ForEach(ScheduleTrigger.Kind.allCases) { k in
                    Text(k.displayName).tag(k)
                }
            }
            .pickerStyle(.segmented).labelsHidden()

            switch triggerKind {
            case .cron:
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Cron expression (5 fields)", text: $cronExpr)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                    HStack(spacing: 4) {
                        ForEach([
                            ("@hourly", "@hourly"),
                            ("@daily 9am", "0 9 * * *"),
                            ("Weekdays 9am", "0 9 * * 1-5"),
                            ("Every 15min", "*/15 * * * *"),
                            ("Mon 10am", "0 10 * * 1")
                        ], id: \.0) { preset in
                            Button(preset.0) { cronExpr = preset.1 }
                                .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                    if let next = CronExpression(cronExpr)?.nextDate(after: Date()) {
                        Text("Next run: \(next, style: .relative) ago / at \(next, style: .time)")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Text("⚠️ Не валидное cron-выражение")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            case .once:
                DatePicker("Run at", selection: $onceAt, in: Date()...)
                    .datePickerStyle(.compact)
            case .onFiveHourReset, .onWeeklyReset:
                Text("Запустится автоматически когда соответствующий лимит сбросится. Приложение должно быть запущено в этот момент.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var targetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Target", "Что запускать")
            Picker("", selection: $targetKind) {
                Text("Agent").tag(TargetKind.agent)
                Text("Workflow").tag(TargetKind.workflow)
            }
            .pickerStyle(.segmented).labelsHidden()
            .frame(width: 240)
            Picker("", selection: $targetName) {
                ForEach(targetOptions(), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
        }
    }

    private func targetOptions() -> [String] {
        switch targetKind {
        case .agent:
            return state.agentsVM.agents.map(\.name).sorted()
        case .workflow:
            return state.workflowsVM.workflows.map(\.name).sorted()
        }
    }

    private var promptRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Prompt message",
                         "То что отправится агенту/orchestrator (для workflow — фраза-trigger)")
            TextEditor(text: $promptMessage)
                .font(.system(.callout, design: .monospaced))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private var backendRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Backend", "Где исполнять")
            Picker("", selection: $backend) {
                ForEach(ScheduleBackend.allCases) { b in
                    Text(b.displayName).tag(b)
                }
            }
            .pickerStyle(.radioGroup).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                if backend == .local {
                    Text("✓ Бесплатно (из обычной квоты). ⚠️ Работает только пока приложение открыто.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("✓ Работает в облаке Anthropic (даже когда комп выключен). ⚠️ Жрёт routine-квоту (5/день на Pro).")
                        .font(.caption).foregroundStyle(.secondary)
                    if triggerKind == .onFiveHourReset || triggerKind == .onWeeklyReset {
                        Text("⚠️ Cloud routines не поддерживают триггеры по событиям — только cron. Переключи trigger на cron.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var enabledRow: some View {
        Toggle(isOn: $enabled) {
            Text("Enabled — будет реально срабатывать")
        }
    }

    private var footer: some View {
        HStack {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle())
            Button(editing == nil ? "Create schedule" : "Save changes") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PressableButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || targetName.isEmpty)
        }
        .padding(20)
    }

    private func sectionLabel(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.callout.weight(.semibold))
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let s = editing {
            name = s.name
            description = s.description
            triggerKind = s.trigger.kind
            switch s.trigger {
            case .cron(let e): cronExpr = e
            case .once(let d): onceAt = d
            default: break
            }
            switch s.target {
            case .agent(let n): targetKind = .agent; targetName = n
            case .workflow(let n): targetKind = .workflow; targetName = n
            }
            promptMessage = s.promptMessage
            backend = s.backend
            enabled = s.enabled
        } else {
            // Defaults
            if targetName.isEmpty {
                targetName = state.agentsVM.agents.first(where: { $0.name != OrchestratorBuilder.agentName })?.name ?? ""
            }
        }
    }

    private func save() {
        let trigger: ScheduleTrigger
        switch triggerKind {
        case .cron:
            guard CronExpression(cronExpr) != nil else {
                error = "Невалидное cron-выражение"
                return
            }
            trigger = .cron(expression: cronExpr)
        case .once:
            trigger = .once(at: onceAt)
        case .onFiveHourReset:
            trigger = .onFiveHourReset
        case .onWeeklyReset:
            trigger = .onWeeklyReset
        }

        let target: ScheduleTarget = targetKind == .agent
            ? .agent(name: targetName)
            : .workflow(name: targetName)

        let schedule = Schedule(
            name: name.trimmingCharacters(in: .whitespaces),
            description: description,
            trigger: trigger,
            target: target,
            promptMessage: promptMessage,
            backend: backend,
            enabled: enabled,
            lastRunAt: editing?.lastRunAt,
            nextRunAt: nil,
            cloudRoutineId: editing?.cloudRoutineId
        )

        do {
            try state.container.scheduleRepository.save(schedule, overwrite: editing != nil)
            state.schedulesVM.scheduler.reload()
            state.schedulesVM.pendingSelectionScheduleId = schedule.name
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
