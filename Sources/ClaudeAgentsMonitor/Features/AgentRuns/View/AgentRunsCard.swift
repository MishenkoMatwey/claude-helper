import SwiftUI

/// Per-project panel of agent runs (resumable / background sessions): live status,
/// output tail, and a Stop button. Reads the same `agent-runs.json` the `cam-agents`
/// MCP server writes, so it reflects whatever the orchestrator launched.
struct AgentRunsCard: View {
    let projectPath: String

    @State private var runs: [AgentRun] = []
    @State private var expanded: Set<String> = []
    @State private var tick = 0

    private var store: AgentRunStore {
        AgentRunStore(path: URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".claude/agents/memory/agent-runs.json"))
    }

    // Poll while anything is running.
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                DesignSectionHeader(title: "Запущенные агенты", icon: "play.circle.fill")
                Spacer()
                if runningCount > 0 {
                    Text("\(runningCount) идёт")
                        .font(DS.Typo.micro).foregroundStyle(DS.Color.success)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(DS.Color.success.opacity(0.15)).clipShape(Capsule())
                }
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Обновить")
            }

            if runs.isEmpty {
                Text("Пока никаких запусков. Оркестратор создаёт их через agent_run / agent_continue.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    .padding(.vertical, DS.Space.xs)
            } else {
                ForEach(runs) { run in runRow(run) }
            }
        }
        .designCard()
        .onAppear(perform: reload)
        .onReceive(timer) { _ in if runningCount > 0 { reload() } }
    }

    private var runningCount: Int { runs.filter { $0.isRunning }.count }

    private func runRow(_ run: AgentRun) -> some View {
        let isOpen = expanded.contains(run.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusDot(run.status)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(run.agent).font(DS.Typo.bodyMedium)
                        if run.background {
                            Text("фон").font(DS.Typo.micro).foregroundStyle(DS.Color.purple)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(DS.Color.purple.opacity(0.15)).clipShape(Capsule())
                        }
                        Text(run.status).font(DS.Typo.micro).foregroundStyle(statusColor(run.status))
                    }
                    Text(run.lastTask).font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(isOpen ? nil : 1)
                }
                Spacer()
                if run.isRunning {
                    Button { stop(run) } label: {
                        Label("Stop", systemImage: "stop.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered).tint(.red).controlSize(.small)
                }
            }
            if isOpen {
                let tail = store.tailLog(run.id)
                if !tail.isEmpty {
                    Text(tail.prefix(2000))
                        .font(DS.Typo.mono).foregroundStyle(DS.Color.textSecondary)
                        .textSelection(.enabled)
                        .padding(DS.Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.Color.surfaceElevated))
                }
            }
        }
        .padding(.horizontal, DS.Space.s).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s)
            .fill(isOpen ? DS.Color.accent.opacity(0.06) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { if isOpen { expanded.remove(run.id) } else { expanded.insert(run.id) } }
    }

    private func statusDot(_ status: String) -> some View {
        Group {
            if status == "running" {
                ProgressView().controlSize(.small)
            } else {
                Circle().fill(statusColor(status)).frame(width: 9, height: 9)
            }
        }
        .frame(width: 16)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "running": return DS.Color.success
        case "done": return DS.Color.accent
        case "failed": return DS.Color.danger
        case "stopped": return DS.Color.textTertiary
        default: return DS.Color.textTertiary
        }
    }

    private func reload() {
        runs = store.reconcileRunning()
    }

    private func stop(_ run: AgentRun) {
        store.stop(run.id)
        reload()
    }
}
