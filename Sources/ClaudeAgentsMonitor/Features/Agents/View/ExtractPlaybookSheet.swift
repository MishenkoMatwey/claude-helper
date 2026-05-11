import SwiftUI

struct ExtractPlaybookSheet: View {
    @EnvironmentObject var state: AppState
    let agent: Agent
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [SessionRef] = []
    @State private var selectedSession: SessionRef?
    @State private var status: String = "Pick a session to extract from."
    @State private var isWorking: Bool = false
    @State private var extractedText: String = ""
    @State private var error: String?
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionPicker
                    runRow
                    resultEditor
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 700)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(.tint).font(.title)
            VStack(alignment: .leading, spacing: 0) {
                Text("Extract playbook for \(agent.name)").font(.title2.bold())
                Text("Claude reads a past session and distills a reusable playbook.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var sessionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Session").font(.callout.weight(.semibold))
                Spacer()
                Button("Reload") { reload() }
                    .controlSize(.small)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sessions) { s in
                        Button {
                            selectedSession = s
                        } label: {
                            HStack {
                                Image(systemName: selectedSession?.id == s.id ? "circle.inset.filled" : "circle")
                                    .foregroundStyle(selectedSession?.id == s.id ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.project)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                    Text(s.modifiedAt, style: .relative)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(s.messageCount) lines")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(selectedSession?.id == s.id ? Color.accentColor.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                    if sessions.isEmpty {
                        Text("No sessions found").font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }
            }
            .frame(height: 180)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var runRow: some View {
        HStack {
            Button {
                runExtraction()
            } label: {
                if isWorking {
                    HStack { ProgressView().controlSize(.small); Text("Extracting…") }
                } else {
                    Label("Extract playbook", systemImage: "wand.and.stars")
                }
            }
            .disabled(isWorking || selectedSession == nil)
            .keyboardShortcut(.defaultAction)
            Spacer()
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var resultEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Extracted playbook (review + edit before saving)")
                .font(.callout.weight(.semibold))
            TextEditor(text: $extractedText)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle())
            Button {
                save()
            } label: {
                Label("Append to playbooks.md", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(extractedText.trimmingCharacters(in: .whitespaces).isEmpty
                      || extractedText.trimmingCharacters(in: .whitespaces) == "SKIP")
        }
        .padding(20)
    }

    private func reload() {
        sessions = PlaybookExtractor.recentSessions(limit: 20)
        selectedSession = sessions.first
    }

    private func runExtraction() {
        guard let session = selectedSession else { return }
        isWorking = true
        error = nil
        extractedText = ""
        Task {
            do {
                let result = try await PlaybookExtractor.extract(
                    from: session,
                    agentName: agent.name,
                    progress: { msg in
                        Task { @MainActor in self.status = msg }
                    }
                )
                await MainActor.run {
                    self.extractedText = result
                    self.isWorking = false
                    if result == "SKIP" {
                        self.status = "Claude returned SKIP — nothing worth saving in this session."
                    } else {
                        self.status = "Extracted. Review above and save."
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isWorking = false
                    self.status = "Failed."
                }
            }
        }
    }

    private func save() {
        let url = state.container.agentRepository.agentsDirectory()
            .appendingPathComponent("memory/\(agent.name).playbooks.md")
        do {
            try PlaybookExtractor.appendPlaybook(
                extractedText.trimmingCharacters(in: .whitespacesAndNewlines),
                to: url
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
