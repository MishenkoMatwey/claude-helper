import SwiftUI
import AppKit

struct MemoryEditorView: View {
    let title: String
    let path: URL
    let placeholder: String

    @State private var content: String = ""
    @State private var newEntry: String = ""
    @State private var didLoad: Bool = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Text(path.path.replacingOccurrences(
                    of: NSHomeDirectory(), with: "~"
                ))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([path])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                TextField("+ remember… (короткая запись, добавится с timestamp)", text: $newEntry, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                Button("Add") { addEntry() }
                    .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextEditor(text: $content)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 220, maxHeight: 380)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .designCard()
        .onAppear { loadIfNeeded() }
        .onChange(of: path) { _, _ in didLoad = false; loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if FileManager.default.fileExists(atPath: path.path) {
            content = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        } else {
            content = placeholder
        }
    }

    private func addEntry() {
        let trimmed = newEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let timestamp = formattedNow()
        let entry = "\n## \(timestamp)\n\(trimmed)\n"
        if content.isEmpty || !content.hasSuffix("\n") {
            content += "\n"
        }
        content += entry
        newEntry = ""
        save()
    }

    private func formattedNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: path, atomically: true, encoding: .utf8)
            status = "Saved \(formattedNow())"
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }
}
