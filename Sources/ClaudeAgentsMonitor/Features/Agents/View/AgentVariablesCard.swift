import SwiftUI

struct AgentVariablesCard: View {
    @EnvironmentObject var state: AppState
    let agentName: String

    @State private var variables: [AgentVariable] = []
    @State private var revealed: [String: String] = [:]
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var newIsSecret: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Variables & Secrets").font(.headline)
                Spacer()
                Text("\(variables.count) total").font(.caption).foregroundStyle(.secondary)
                Button { reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            Text("Plain → JSON file. Secret → macOS Keychain (`security` CLI). The agent can fetch them via Bash.")
                .font(.caption2).foregroundStyle(.secondary)

            if variables.isEmpty {
                Text("No variables yet — add one below.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(variables) { v in
                        variableRow(v)
                    }
                }
            }

            Divider()
            addRow

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { reload() }
        .onChange(of: agentName) { _, _ in reload() }
    }

    private func variableRow(_ v: AgentVariable) -> some View {
        HStack(spacing: 8) {
            Image(systemName: v.isSecret ? "lock.fill" : "doc.text")
                .foregroundStyle(v.isSecret ? Color.orange : .secondary)
                .frame(width: 16)
            Text(v.key)
                .font(.system(.callout, design: .monospaced).bold())
                .frame(width: 180, alignment: .leading)
            Group {
                if v.isSecret {
                    if let value = revealed[v.key] {
                        Text(value)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("••••••••").foregroundStyle(.secondary)
                    }
                } else {
                    Text(v.value)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            if v.isSecret {
                Button {
                    if revealed[v.key] != nil {
                        revealed.removeValue(forKey: v.key)
                    } else if let value = state.container.agentVariables.revealSecret(key: v.key, for: agentName) {
                        revealed[v.key] = value
                    } else {
                        error = "Failed to read secret '\(v.key)' (Keychain denied)"
                    }
                } label: {
                    Image(systemName: revealed[v.key] != nil ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealed[v.key] != nil ? "Hide" : "Reveal")

                Button {
                    if let value = revealed[v.key] ?? state.container.agentVariables.revealSecret(key: v.key, for: agentName) {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(value, forType: .string)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            } else {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(v.value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            Button {
                state.container.agentVariables.delete(key: v.key, for: agentName)
                revealed.removeValue(forKey: v.key)
                reload()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add variable").font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                TextField("KEY (UPPER_SNAKE)", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Group {
                    if newIsSecret {
                        SecureField("value", text: $newValue)
                    } else {
                        TextField("value", text: $newValue)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Toggle(isOn: $newIsSecret) {
                    Label("secret", systemImage: "lock.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                Button {
                    addVariable()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty
                          || newValue.isEmpty)
            }
        }
    }

    private func addVariable() {
        do {
            try state.container.agentVariables.save(
                key: newKey.trimmingCharacters(in: .whitespaces),
                value: newValue,
                isSecret: newIsSecret,
                for: agentName
            )
            newKey = ""
            newValue = ""
            newIsSecret = false
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reload() {
        variables = state.container.agentVariables.loadAll(for: agentName)
    }
}
