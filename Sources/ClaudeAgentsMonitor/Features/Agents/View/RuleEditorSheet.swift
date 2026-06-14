import SwiftUI

/// Add / edit a single rule. The caller stores the result via `onSave`.
struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var rule: AgentRule
    let onSave: (AgentRule) -> Void
    let onDelete: (() -> Void)?

    /// All existing rule ids (to flag dup ids at form time).
    let existingIds: Set<String>
    let isNew: Bool

    @State private var error: String?

    init(
        rule: AgentRule,
        existingIds: Set<String>,
        isNew: Bool,
        onSave: @escaping (AgentRule) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self._rule = State(initialValue: rule)
        self.existingIds = existingIds
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isNew ? "Add rule" : "Edit rule").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("ID (kebab-case)", text: $rule.id, placeholder: "sql-injection-string-concat")
                    severityRow
                    field("Category", text: $rule.category, placeholder: "security, performance, style…")
                    field("Title", text: $rule.title, placeholder: "Короткое название правила")
                    multilineField("Pattern", text: $rule.pattern, placeholder: "Что искать в коде / PR")
                    multilineField("Example", text: $rule.example, placeholder: "Пример нарушения (код)")
                    multilineField("Why", text: $rule.rationale, placeholder: "Почему это важно")
                    multilineField("Fix", text: $rule.fix, placeholder: "Как исправлять")
                }
            }
            .frame(minHeight: 360, maxHeight: 460)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }

            HStack {
                if let onDelete, !isNew {
                    Button {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var isValid: Bool {
        let trimmedId = rule.id.trimmingCharacters(in: .whitespaces)
        let trimmedTitle = rule.title.trimmingCharacters(in: .whitespaces)
        return !trimmedId.isEmpty && !trimmedTitle.isEmpty
    }

    private var severityRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Severity").font(.caption.weight(.semibold))
            Picker("", selection: $rule.severity) {
                ForEach(RuleSeverity.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func multilineField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold))
            TextEditor(text: text)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 56, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .font(.system(.callout, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func save() {
        var r = rule
        r.id = r.id.trimmingCharacters(in: .whitespaces)
        r.category = r.category.trimmingCharacters(in: .whitespaces)
        r.title = r.title.trimmingCharacters(in: .whitespaces)
        if isNew && existingIds.contains(r.id) {
            error = "Rule with id '\(r.id)' already exists. Pick a different id."
            return
        }
        onSave(r)
        dismiss()
    }
}
