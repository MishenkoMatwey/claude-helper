import SwiftUI

struct RenameProjectSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let project: ClaudeProject
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack {
                Image(systemName: "pencil.line").foregroundStyle(DS.Color.accent)
                Text("Rename project").font(DS.Typo.title)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SubtleTextButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Display name").font(DS.Typo.captionMedium)
                TextField(project.name, text: $newName)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Path stays the same: \(project.path)")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Color.textTertiary)
            HStack {
                Spacer()
                Button("Rename") {
                    state.projectsVM.renameProject(project, to: newName)
                    dismiss()
                }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 460)
        .onAppear { newName = project.name }
    }
}
