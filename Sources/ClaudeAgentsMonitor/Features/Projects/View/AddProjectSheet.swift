import SwiftUI
import AppKit

struct AddProjectSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var path: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                nameRow
                pathRow
                infoCard
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 600, height: 460)
    }

    private var header: some View {
        HStack {
            Image(systemName: "folder.fill.badge.plus").foregroundStyle(.tint).font(.title)
            Text("Add project").font(.title2.bold())
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle()).keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display name").font(.callout.weight(.semibold))
            TextField("e.g. clussters, budget-app, poker", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var pathRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project folder").font(.callout.weight(.semibold))
            HStack {
                TextField("/Users/.../path/to/project", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                Button("Browse…") { browseFolder() }
            }
            if !path.isEmpty {
                Text("Агенты будут лежать в `\(path)/.claude/agents/`")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Что произойдёт при добавлении:").font(.caption.weight(.semibold))
            bullet("Создастся каталог `.claude/agents/` в проекте")
            bullet("Создастся пустой `SHARED.md` для этого проекта")
            bullet("В `.claude/settings.local.json` добавится SessionStart hook — Claude Code будет грузить project SHARED.md в каждой сессии в этой папке")
            bullet("Агенты из ~/.claude/ (User global) останутся доступны как fallback")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("•")
            Text(text).font(.caption)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle())
            Button {
                add()
            } label: { Label("Add project", systemImage: "checkmark.circle.fill") }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || path.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose project folder"
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            if name.isEmpty { name = url.lastPathComponent }
        }
    }

    private func add() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPath = path.trimmingCharacters(in: .whitespaces)
        let url = URL(fileURLWithPath: trimmedPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            error = "Папка не существует или не является директорией: \(trimmedPath)"
            return
        }
        if state.projectsVM.registeredProjects.contains(where: { $0.path == url.path }) {
            error = "Проект с таким путём уже добавлен"
            return
        }
        state.projectsVM.addProject(name: trimmedName, path: url)
        dismiss()
    }
}
