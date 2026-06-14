import SwiftUI

/// Modal: user pastes one or many MR refs (URL / !N / #N), optional note, hits Start.
struct NewReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var queue: ReviewQueueService
    let projectPath: String
    let onStart: (ReviewJob) -> Void

    @State private var refsText: String = ""
    @State private var note: String = ""
    @State private var error: String?

    private var parsedRefs: [String] {
        refsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map(normalize)
    }

    private func normalize(_ ref: String) -> String {
        // strip surrounding quotes / commas / trailing punctuation
        var s = ref
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,;\"'"))
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review MRs").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
            }
            Text("Если несколько — будут отревьюены в связке (одна фича в нескольких сервисах).")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("MR refs (по одному на строку)").font(.caption.weight(.semibold))
                TextEditor(text: $refsText)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 110, maxHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    .overlay(alignment: .topLeading) {
                        if refsText.isEmpty {
                            Text("URL https://gitlab.../merge_requests/838\n!123\n#45\nhttps://github.com/.../pull/12")
                                .foregroundStyle(.tertiary)
                                .font(.system(.callout, design: .monospaced))
                                .padding(.horizontal, 5).padding(.top, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Note (необязательно — доп. контекст для агента)").font(.caption.weight(.semibold))
                TextField("например: «прогон по security», ...", text: $note)
                    .textFieldStyle(.roundedBorder)
            }

            Label("Агент пишет только комменты и резолвит свои треды (только при re-review когда автор пофиксил). Approve / merge / request-changes / draft самого MR — никогда.", systemImage: "lock.shield.fill")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }

            HStack {
                Text(parsedRefs.isEmpty ? "ничего не выбрано" : "\(parsedRefs.count) MR" + (parsedRefs.count > 1 ? "s" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Start review") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedRefs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func start() {
        let refs = parsedRefs
        guard !refs.isEmpty else { return }
        let mrs = refs.map { ReviewMR(ref: $0) }
        let job = ReviewJob(
            id: ReviewQueueService.makeId(),
            projectPath: projectPath,
            mrs: mrs,
            status: .queued,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
            parentJobId: nil,
            startedAt: Date(),
            finishedAt: nil,
            pid: nil,
            logFile: nil
        )
        queue.enqueue(job)
        onStart(job)
        dismiss()
    }
}
