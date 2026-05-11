import SwiftUI

struct MinedResult: Identifiable {
    let id: String
    let session: SessionRef
    var status: Status
    var text: String
    var keep: Bool
    var error: String?

    enum Status: Equatable {
        case pending, running, done, skipped, failed
    }
}

struct MinePlaybooksSheet: View {
    @EnvironmentObject var state: AppState
    let agent: Agent
    @Environment(\.dismiss) private var dismiss

    @State private var sessionLimit: Double = 5
    @State private var results: [MinedResult] = []
    @State private var isRunning: Bool = false
    @State private var currentIndex: Int = -1
    @State private var saveError: String?
    @State private var saved: Int = 0

    private var keepableCount: Int {
        results.filter { $0.status == .done && $0.keep }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controlsRow
                    progressSummary
                    resultsList
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 820, height: 720)
    }

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.stack.badge.plus")
                .foregroundStyle(.tint).font(.title)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mine playbooks for \(agent.name)").font(.title2.bold())
                Text("Прогоняет последние сессии через Claude и собирает все playbook'и которые нашлись.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var controlsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sessions to scan: \(Int(sessionLimit))")
                    .font(.callout.weight(.semibold))
                Slider(value: $sessionLimit, in: 1...20, step: 1)
                    .frame(maxWidth: 240)
                    .disabled(isRunning)
                Spacer()
                Button {
                    run()
                } label: {
                    if isRunning {
                        HStack { ProgressView().controlSize(.small); Text("Running…") }
                    } else {
                        Label("Mine \(Int(sessionLimit)) sessions", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isRunning)
            }
            Text("Каждая сессия = один вызов `claude -p`. Жрёт твои токены — начни с 3-5.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressSummary: some View {
        if !results.isEmpty {
            let done = results.filter { $0.status == .done }.count
            let skipped = results.filter { $0.status == .skipped }.count
            let failed = results.filter { $0.status == .failed }.count
            let pending = results.filter { $0.status == .pending || $0.status == .running }.count
            HStack(spacing: 16) {
                stat("Found", "\(done)", .green)
                stat("Skipped", "\(skipped)", .secondary)
                stat("Failed", "\(failed)", .orange)
                stat("Pending", "\(pending)", .blue)
                Spacer()
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.title3, design: .rounded).bold()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Results").font(.callout.weight(.semibold))
            if results.isEmpty {
                Text("Жми Mine — сессии появятся здесь по мере обработки.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach($results) { $r in
                    resultRow(r: $r)
                }
            }
        }
    }

    private func resultRow(r: Binding<MinedResult>) -> some View {
        let result = r.wrappedValue
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                statusIcon(result.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.session.project)
                        .font(.system(.caption, design: .monospaced)).lineLimit(1)
                    Text(result.session.modifiedAt, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
                    if let err = result.error {
                        Text(err).font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer()
                if result.status == .done {
                    Toggle(isOn: r.keep) { Text("keep").font(.caption) }
                        .toggleStyle(.checkbox)
                }
            }
            if result.status == .done {
                ScrollView {
                    Text(result.text)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(maxHeight: 140)
                .background(DS.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusIcon(_ s: MinedResult.Status) -> some View {
        switch s {
        case .pending: return AnyView(Image(systemName: "clock").foregroundStyle(.secondary))
        case .running: return AnyView(ProgressView().controlSize(.small))
        case .done: return AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(.green))
        case .skipped: return AnyView(Image(systemName: "minus.circle").foregroundStyle(.secondary))
        case .failed: return AnyView(Image(systemName: "xmark.circle.fill").foregroundStyle(.orange))
        }
    }

    private var footer: some View {
        HStack {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            if saved > 0 {
                Label("Saved \(saved) playbook(s)", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            }
            Spacer()
            Button("Close") { dismiss() }
            Button {
                saveSelected()
            } label: {
                Label("Save \(keepableCount) selected", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(keepableCount == 0)
        }
        .padding(20)
    }

    private func run() {
        let limit = Int(sessionLimit)
        let sessions = PlaybookExtractor.recentSessions(limit: limit)
        results = sessions.map {
            MinedResult(id: $0.id, session: $0, status: .pending, text: "", keep: true)
        }
        isRunning = true
        saved = 0

        Task {
            for index in results.indices {
                await MainActor.run {
                    currentIndex = index
                    results[index].status = .running
                }
                do {
                    let text = try await PlaybookExtractor.extract(
                        from: results[index].session,
                        agentName: agent.name,
                        progress: { _ in }
                    )
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        if trimmed == "SKIP" || trimmed.isEmpty {
                            results[index].status = .skipped
                            results[index].keep = false
                        } else {
                            results[index].text = trimmed
                            results[index].status = .done
                            results[index].keep = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        results[index].status = .failed
                        results[index].error = error.localizedDescription
                        results[index].keep = false
                    }
                }
            }
            await MainActor.run {
                isRunning = false
                currentIndex = -1
            }
        }
    }

    private func saveSelected() {
        let kept = results.filter { $0.status == .done && $0.keep }
        guard !kept.isEmpty else { return }
        let url = state.container.agentRepository.agentsDirectory()
            .appendingPathComponent("memory/\(agent.name).playbooks.md")
        var savedCount = 0
        for r in kept {
            do {
                try PlaybookExtractor.appendPlaybook(r.text, to: url)
                savedCount += 1
            } catch {
                saveError = "\(error.localizedDescription)"
            }
        }
        saved = savedCount
        // Mark saved entries as no longer keepable so footer button disables.
        for r in kept {
            if let i = results.firstIndex(where: { $0.id == r.id }) {
                results[i].keep = false
            }
        }
    }
}
