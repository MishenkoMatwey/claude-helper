import SwiftUI

/// Modal: launch a re-review of an already-completed job.
/// Re-review = classifier flow (resolve / reply / keep_open / new_issues) + delete & repost
/// the top-level `[SUMMARY]` comment. Optional fresh note overrides parent's note.
struct ReReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var queue: ReviewQueueService
    let parent: ReviewJob
    let onStart: (ReviewJob) -> Void

    @State private var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Re-review MR").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
            }
            Text("Классификатор existing-тредов (resolve/reply/keep_open) + delta-only новые findings. Старый [SUMMARY] коммент будет удалён и заменён новым.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("MR refs").font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(parent.mrs) { mr in
                        Text(mr.ref)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Доп. контекст для re-review (необязательно — заменит note прошлого прохода)").font(.caption.weight(.semibold))
                TextEditor(text: $note)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text(placeholderForNote)
                                .foregroundStyle(.tertiary)
                                .font(.system(.callout, design: .monospaced))
                                .padding(.horizontal, 5).padding(.top, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Label("Resolve тредов разрешён там, где автор пофиксил. Approve / merge / state самого MR — никогда.", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("parent: \(parent.id)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Start re-review") { start() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var placeholderForNote: String {
        if let prev = parent.note, !prev.isEmpty {
            return "прошлый note:\n\(prev)\n\n(оставь пусто — унаследует прошлый)"
        }
        return "например: «обрати внимание на ответы автора по null-safety», «забудь про прошлые SQL findings»"
    }

    private func start() {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        let noteOverride = trimmed.isEmpty ? nil : trimmed
        let fresh = queue.enqueueReReview(of: parent, note: noteOverride)
        onStart(fresh)
        dismiss()
    }
}
