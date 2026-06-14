import SwiftUI
import AppKit

/// Self-contained sheet for creating an agent from a template.
/// Independent from NewAgentSheet — all template-specific logic lives here.
struct TemplateAgentSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let template: AgentTemplate

    @State private var name: String = ""
    @State private var plainValues: [String: String] = [:]
    @State private var secretValues: [String: String] = [:]
    @State private var validated: Bool = false
    @State private var validating: Bool = false
    @State private var validationOutput: String = ""
    @State private var autoInstallPlugins: Bool = true
    @State private var error: String?
    @State private var didInit: Bool = false
    // Per-connection-slot verify state.
    @State private var slotValidated: [String: Bool] = [:]
    @State private var slotValidating: [String: Bool] = [:]
    @State private var slotOutput: [String: String] = [:]
    @State private var expandedOutput: Set<String> = []
    /// Discovered databases per slot (from `DATABASES_DISCOVERED:` marker in verify output).
    @State private var slotDiscoveredDbs: [String: [String]] = [:]
    /// CLI install state — keyed by tool name ("psql", "mysql", "sqlcmd"). Drives the "Install …"
    /// button that appears when verify reports the tool missing.
    @State private var cliInstalling: Set<String> = []
    @State private var cliInstallLog: [String: String] = [:]
    /// Post-create script (e.g. DB schema discovery) state.
    @State private var postCreateRunning: Bool = false
    @State private var postCreateOutput: String = ""
    @State private var postCreateDone: Bool = false
    @State private var postCreateExitCode: Int32 = 0
    /// Which connection slots are currently visible. First one is always visible.
    @State private var visibleSlots: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    if postCreateRunning || postCreateDone {
                        postCreateCard
                    }
                    summaryCard
                    identityCard
                    if !template.plainVarsToSetup.isEmpty {
                        plainVarsCard
                    }
                    if !template.secretsToSetup.isEmpty {
                        secretsCard
                    }
                    if !template.connections.isEmpty {
                        connectionsSection
                    }
                    if let v = template.validation {
                        validationCard(v)
                    }
                    pluginsCard
                }
                .padding(DS.Space.l)
            }
            .background(DS.Color.bg)
            Divider()
            footer
        }
        .frame(width: 760, height: 800)
        .onAppear { initializeIfNeeded() }
    }

    // MARK: - Sections

    private var header: some View {
        let tint = providerColor(template.color)
        return HStack(spacing: DS.Space.s) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(tint.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    )
                    .frame(width: 40, height: 40)
                TemplateIcon(
                    assetIcon: template.assetIcon,
                    sfSymbol: template.icon,
                    tint: tint,
                    size: 22
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Create from template — \(template.name)").font(DS.Typo.title)
                Text(template.description).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SubtleTextButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(DS.Space.l)
        .background(DS.Color.surface)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: "info.circle.fill").foregroundStyle(DS.Color.accent)
                Text("What will be created").font(DS.Typo.headline)
            }
            bullet("Subagent file in `~/.claude/agents/\(trimmedName.isEmpty ? template.name : trimmedName).md` with model `\(template.model)` and tools/permissions baked in.")
            if !template.bashPresetIds.isEmpty {
                bullet("Bash permissions from presets: " + template.bashPresetIds.map { "**\($0)**" }.joined(separator: ", "))
            }
            if !template.suggestedPluginIds.isEmpty {
                bullet("Suggested plugins: " + template.suggestedPluginIds.joined(separator: ", "))
            }
            if !template.plainVarsToSetup.isEmpty || !template.secretsToSetup.isEmpty {
                bullet("Variables → `<name>.vars.json` · secrets → macOS Keychain.")
            }
        }
        .designCard()
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: "person.crop.circle").foregroundStyle(DS.Color.accent)
                Text("Identity").font(DS.Typo.headline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(DS.Typo.captionMedium)
                TextField("e.g. \(template.name)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typo.monoSmall)
                Text("Lowercase, digits, hyphen — used as filename.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .designCard()
    }

    private var plainVarsCard: some View {
        let tint = providerColor(template.color)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: template.icon)
                        .foregroundStyle(tint).font(.system(size: 12, weight: .semibold))
                }
                Text("Plain variables").font(DS.Typo.headline)
                Spacer()
                Text("→ \(trimmedName.isEmpty ? template.name : trimmedName).vars.json")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            ForEach(template.plainVarsToSetup, id: \.key) { field in
                if field.isFolder {
                    folderFieldRow(field)
                } else {
                    fieldRow(
                        field.isOptional ? "\(field.label) (optional)" : field.label,
                        key: field.key, help: field.help, isSecret: false,
                        placeholder: field.defaultValue,
                        binding: Binding(
                            get: { plainValues[field.key] ?? "" },
                            set: { plainValues[field.key] = $0; validated = false }
                        )
                    )
                }
            }
        }
        .designCard()
    }

    private var secretsCard: some View {
        let tint = providerColor(template.color)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: template.icon)
                        .foregroundStyle(tint).font(.system(size: 12, weight: .semibold))
                }
                Image(systemName: "lock.fill").foregroundStyle(DS.Color.warning)
                Text("Tokens").font(DS.Typo.headline)
                Spacer()
                Text("→ macOS Keychain").font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            if template.secretsToSetup.contains(where: { $0.isOptional }) {
                Text("Fill the field that matches your host. You can leave the other empty.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
            }
            ForEach(template.secretsToSetup, id: \.key) { field in
                providerSecretField(field)
            }
        }
        .designCard()
    }

    private func providerSecretField(_ field: SecretField) -> some View {
        let accent = providerColor(field.providerColor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: field.providerIcon ?? "lock.fill")
                        .foregroundStyle(accent).font(.system(size: 13, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(field.providerName ?? field.label).font(DS.Typo.bodyMedium)
                        if field.isOptional {
                            Text("optional").font(DS.Typo.micro)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(DS.Color.textTertiary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(field.label).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Text(field.key).font(DS.Typo.monoSmall).foregroundStyle(DS.Color.textTertiary)
            }
            SecureField(field.placeholder, text: Binding(
                get: { secretValues[field.key] ?? "" },
                set: { secretValues[field.key] = $0; validated = false }
            ))
            .textFieldStyle(.roundedBorder)
            Text(field.help).font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Space.s)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.s)
                .fill(accent.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Post-create progress (e.g. schema discovery)

    private var postCreateCard: some View {
        let tint = providerColor(template.color)
        let label = template.postCreateLabel
        let ok = postCreateDone && postCreateExitCode == 0
        let bad = postCreateDone && postCreateExitCode != 0
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: 8) {
                if postCreateRunning {
                    ProgressView().controlSize(.small)
                } else if ok {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.Color.success)
                } else if bad {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.Color.warning)
                }
                Text(postCreateRunning ? label : (ok ? "Setup complete" : "Setup finished with errors"))
                    .font(DS.Typo.headline)
                Spacer()
            }
            if !postCreateOutput.isEmpty {
                ScrollView {
                    Text(postCreateOutput)
                        .font(DS.Typo.monoSmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 220)
                .background(DS.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
            }
            HStack {
                Spacer()
                if postCreateRunning {
                    Button("Continue in background") {
                        // Detach: keep the shell running, close the sheet. Schema file will appear
                        // when finished — the user can re-open the agent to see it.
                        state.refresh()
                        dismiss()
                    }
                    .buttonStyle(SubtleTextButtonStyle())
                } else {
                    Button("Done") {
                        state.refresh()
                        dismiss()
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .fill(tint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Connection slots (database-style multi-DB block UI)

    private var connectionsSection: some View {
        let tint = providerColor(template.color)
        let visible = template.connections.filter { visibleSlots.contains($0.slotId) }
        let nextHidden = template.connections.first { !visibleSlots.contains($0.slotId) }
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "cylinder.split.1x2.fill")
                        .foregroundStyle(tint).font(.system(size: 12, weight: .semibold))
                }
                Text("Connections").font(DS.Typo.headline)
                Text("\(visible.count)")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                Label("READ-ONLY", systemImage: "lock.shield.fill")
                    .font(DS.Typo.micro)
                    .foregroundStyle(DS.Color.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        Capsule().fill(DS.Color.success.opacity(0.12))
                            .overlay(Capsule().stroke(DS.Color.success.opacity(0.35), lineWidth: 1))
                    )
                Spacer()
                Text("Each slot verifies independently")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, 2)
            ForEach(visible) { conn in
                connectionBlock(conn, tint: tint)
            }
            if let next = nextHidden {
                Button {
                    visibleSlots.insert(next.slotId)
                    if plainValues[next.schemeKey]?.isEmpty ?? true {
                        plainValues[next.schemeKey] = next.schemeOptions.first ?? ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(tint)
                        Text("Add connection").font(DS.Typo.bodyMedium).foregroundStyle(tint)
                        Spacer()
                        Text("\(template.connections.count - visible.count) slot(s) available")
                            .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.m)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.m)
                            .fill(tint.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.m)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(tint.opacity(0.45))
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("All \(template.connections.count) slots in use.")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, 2)
            }
        }
    }

    /// Clear all stored values + verify state for a slot and hide it.
    private func removeConnection(_ c: ConnectionField) {
        let plainKeys = [c.aliasKey, c.schemeKey, c.hostKey, c.userKey, c.databaseKey]
        for k in plainKeys { plainValues[k] = "" }
        secretValues[c.passwordKey] = ""
        slotValidated[c.slotId] = false
        slotValidating[c.slotId] = false
        slotOutput.removeValue(forKey: c.slotId)
        expandedOutput.remove(c.slotId)
        visibleSlots.remove(c.slotId)
    }

    @ViewBuilder
    private func connectionBlock(_ c: ConnectionField, tint: Color) -> some View {
        let isValidated = slotValidated[c.slotId] == true
        let isValidating = slotValidating[c.slotId] == true
        let output = slotOutput[c.slotId] ?? ""
        let missing = connectionMissingFields(c)
        let canVerify = missing.isEmpty
        let aliasPreview = (plainValues[c.aliasKey] ?? "").trimmingCharacters(in: .whitespaces)
        let hasInput = slotHasInput(c)

        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: 8) {
                Image(systemName: isValidated ? "checkmark.seal.fill" : "circle.dashed")
                    .foregroundStyle(isValidated ? DS.Color.success : DS.Color.textTertiary)
                Text(c.title).font(DS.Typo.bodyMedium)
                if !aliasPreview.isEmpty {
                    Text("·").foregroundStyle(DS.Color.textTertiary)
                    Text(aliasPreview).font(DS.Typo.mono).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                if c.isOptional {
                    Text("optional").font(DS.Typo.micro)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(DS.Color.textTertiary.opacity(0.15))
                        .clipShape(Capsule())
                }
                if isValidated {
                    Label("verified", systemImage: "checkmark.circle.fill")
                        .font(DS.Typo.caption).foregroundStyle(DS.Color.success)
                }
                if c.isOptional {
                    Button {
                        removeConnection(c)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.Color.textTertiary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Remove this connection")
                }
            }

            HStack(alignment: .top, spacing: DS.Space.s) {
                slotPlainField(label: "Alias", icon: "tag.fill",
                               key: c.aliasKey, placeholder: "main, analytics, …")
                slotSchemePicker(c)
            }
            HStack(alignment: .top, spacing: DS.Space.s) {
                slotPlainField(label: "Host", icon: "network",
                               key: c.hostKey, placeholder: schemePlaceholder(c, field: .host))
                slotPlainField(label: "Databases", icon: "cylinder",
                               key: c.databaseKey, placeholder: schemePlaceholder(c, field: .db))
            }
            HStack(alignment: .top, spacing: DS.Space.s) {
                slotPlainField(label: "User", icon: "person.fill",
                               key: c.userKey, placeholder: "ro_user")
                slotSecretField(label: "Password", icon: "key.fill",
                                key: c.passwordKey, placeholder: "••••")
            }

            HStack(spacing: DS.Space.s) {
                Button {
                    runSlotVerify(c)
                } label: {
                    if isValidating {
                        HStack { ProgressView().controlSize(.small); Text("Verifying…") }
                    } else {
                        Label("Verify connection", systemImage: "play.fill")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isValidating || !canVerify)

                if !canVerify {
                    Text("Missing: \(missing.joined(separator: ", "))")
                        .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                } else if !hasInput {
                    Text("Empty slot — leave blank if unused.")
                        .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                if !output.isEmpty {
                    Button(expandedOutput.contains(c.slotId) ? "Hide log" : "Show log") {
                        if expandedOutput.contains(c.slotId) {
                            expandedOutput.remove(c.slotId)
                        } else {
                            expandedOutput.insert(c.slotId)
                        }
                    }
                    .buttonStyle(SubtleTextButtonStyle())
                }
            }

            if !output.isEmpty && expandedOutput.contains(c.slotId) {
                ScrollView {
                    Text(output)
                        .font(DS.Typo.monoSmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(DS.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
            }
            if let missing = missingCLIInOutput(output) {
                installCLIBanner(tool: missing, tint: tint)
            }
            if let discovered = slotDiscoveredDbs[c.slotId], !discovered.isEmpty {
                discoveredDbsView(slot: c, dbs: discovered, tint: tint)
            }
        }
        .padding(DS.Space.m)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.m)
                    .fill(isValidated ? DS.Color.success.opacity(0.06) : DS.Color.surface)
                RoundedRectangle(cornerRadius: DS.Radius.m)
                    .strokeBorder(
                        isValidated ? DS.Color.success.opacity(0.40) : DS.Color.border,
                        lineWidth: isValidated ? 1.5 : 1
                    )
            }
        )
        .animation(.easeOut(duration: 0.15), value: isValidated)
    }

    /// Detect "<tool> not installed" hint in verify output. Returns the tool key the user can install.
    private func missingCLIInOutput(_ output: String) -> String? {
        if output.contains("psql not installed") { return "psql" }
        if output.contains("mysql CLI not installed") { return "mysql" }
        if output.contains("sqlcmd not installed") { return "sqlcmd" }
        return nil
    }

    private func brewCommand(for tool: String) -> (label: String, command: String) {
        switch tool {
        case "psql":
            return ("brew install libpq",
                    "brew install libpq && brew link --force libpq")
        case "mysql":
            return ("brew install mysql-client",
                    "brew install mysql-client && brew link --force mysql-client")
        case "sqlcmd":
            return ("brew install mssql-tools18",
                    "brew tap microsoft/mssql-release && brew install --no-quarantine msodbcsql18 mssql-tools18")
        default:
            return ("brew install \(tool)", "brew install \(tool)")
        }
    }

    @ViewBuilder
    private func installCLIBanner(tool: String, tint: Color) -> some View {
        let cmd = brewCommand(for: tool)
        let installing = cliInstalling.contains(tool)
        let log = cliInstallLog[tool] ?? ""
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(DS.Color.warning).font(.system(size: 11, weight: .semibold))
                Text("`\(tool)` is required for SELECT 1 + database discovery")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Button {
                    installCLI(tool: tool)
                } label: {
                    if installing {
                        HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Installing…") }
                    } else {
                        Label("Install \(tool)", systemImage: "arrow.down.circle.fill")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(installing)
            }
            Text(cmd.label)
                .font(DS.Typo.monoSmall)
                .foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.Color.surfaceElevated))
            if !log.isEmpty {
                ScrollView {
                    Text(log)
                        .font(DS.Typo.monoSmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(maxHeight: 120)
                .background(DS.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
            }
        }
        .padding(.top, 4)
    }

    private func installCLI(tool: String) {
        guard !cliInstalling.contains(tool) else { return }
        let cmd = brewCommand(for: tool).command
        cliInstalling.insert(tool)
        cliInstallLog[tool] = "Running: \(cmd)\n"
        Task.detached {
            // brew installs need more wall-clock time than verify; 5 minutes is plenty.
            let result = await Self.runShell(cmd, timeoutSec: 300)
            await MainActor.run {
                cliInstalling.remove(tool)
                cliInstallLog[tool] = result.output
            }
        }
    }

    @ViewBuilder
    private func discoveredDbsView(slot c: ConnectionField, dbs: [String], tint: Color) -> some View {
        let selected = Set(currentDatabasesCSV(c))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text("Discovered on host (click to add/remove)")
                    .font(DS.Typo.captionMedium)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Button("Use all") {
                    setDatabasesCSV(c, dbs)
                }
                .buttonStyle(SubtleTextButtonStyle())
                .disabled(selected == Set(dbs))
                Button("Clear") {
                    setDatabasesCSV(c, [])
                }
                .buttonStyle(SubtleTextButtonStyle())
                .disabled(selected.isEmpty)
            }
            FlowLayout(spacing: 6) {
                ForEach(dbs, id: \.self) { db in
                    let isOn = selected.contains(db)
                    Button {
                        toggleDatabaseInList(c, db)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text(db).font(DS.Typo.mono)
                        }
                        .foregroundStyle(isOn ? Color.white : tint)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isOn ? tint : tint.opacity(0.10))
                                .overlay(Capsule().stroke(tint.opacity(isOn ? 0 : 0.35), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private enum SlotFieldHint { case host, db }

    private func schemePlaceholder(_ c: ConnectionField, field: SlotFieldHint) -> String {
        let scheme = (plainValues[c.schemeKey] ?? "").lowercased()
        switch (scheme, field) {
        case ("postgres", .host), ("postgresql", .host): return "db.host:5432"
        case ("mysql", .host), ("mariadb", .host):       return "db.host:3306"
        case ("clickhouse", .host):                      return "db.host:8123"
        case ("mssql", .host), ("sqlserver", .host):     return "db.host:1433"
        case ("sqlite", .host):                          return "/absolute/path/file.db"
        case (_, .db):
            return scheme == "sqlite" ? "(unused)" : "dbname  (or: db1, db2, db3)"
        default: return ""
        }
    }

    private func slotFieldLabel(_ label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 12)
            Text(label).font(DS.Typo.captionMedium)
            Spacer(minLength: 0)
        }
    }

    private func slotPlainField(label: String, icon: String, key: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            slotFieldLabel(label, icon: icon)
            TextField(placeholder, text: Binding(
                get: { plainValues[key] ?? "" },
                set: { plainValues[key] = $0; slotValidated[keyToSlot(key)] = false }
            ))
            .textFieldStyle(.roundedBorder)
            .font(DS.Typo.monoSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slotSchemePicker(_ c: ConnectionField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            slotFieldLabel("Scheme", icon: "rectangle.connected.to.line.below")
            Picker("", selection: Binding(
                get: { plainValues[c.schemeKey] ?? c.schemeOptions.first ?? "" },
                set: { plainValues[c.schemeKey] = $0; slotValidated[c.slotId] = false }
            )) {
                ForEach(c.schemeOptions, id: \.self) { s in
                    Text(s).tag(s)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slotSecretField(label: String, icon: String, key: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            slotFieldLabel(label, icon: icon)
            SecureField(placeholder, text: Binding(
                get: { secretValues[key] ?? "" },
                set: { secretValues[key] = $0; slotValidated[keyToSlot(key)] = false }
            ))
            .textFieldStyle(.roundedBorder)
            .font(DS.Typo.monoSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Map any of a connection's keys back to its slotId by prefix match.
    private func keyToSlot(_ key: String) -> String {
        for c in template.connections {
            let keys = [c.aliasKey, c.schemeKey, c.hostKey, c.userKey, c.passwordKey, c.databaseKey]
            if keys.contains(key) { return c.slotId }
        }
        return key
    }

    private func runSlotVerify(_ c: ConnectionField) {
        let ws = CharacterSet.whitespacesAndNewlines
        let alias = (plainValues[c.aliasKey] ?? "").trimmingCharacters(in: ws)
        let scheme = (plainValues[c.schemeKey] ?? "").trimmingCharacters(in: ws)
        let host = (plainValues[c.hostKey] ?? "").trimmingCharacters(in: ws)
        let user = (plainValues[c.userKey] ?? "").trimmingCharacters(in: ws)
        let pass = Self.cleanSecret((secretValues[c.passwordKey] ?? "").trimmingCharacters(in: ws))
        let db = (plainValues[c.databaseKey] ?? "").trimmingCharacters(in: ws)

        var cmd = c.verifyCommand
        cmd = cmd.replacingOccurrences(of: "{ALIAS}", with: alias)
        cmd = cmd.replacingOccurrences(of: "{SCHEME}", with: scheme)
        cmd = cmd.replacingOccurrences(of: "{HOST}", with: host)
        cmd = cmd.replacingOccurrences(of: "{USER}", with: user)
        cmd = cmd.replacingOccurrences(of: "{PASSWORD}", with: pass)
        cmd = cmd.replacingOccurrences(of: "{DATABASE}", with: db)

        slotValidating[c.slotId] = true
        slotOutput[c.slotId] = "Running…"
        slotDiscoveredDbs.removeValue(forKey: c.slotId)
        expandedOutput.insert(c.slotId)
        Task.detached {
            let result = await Self.runShell(cmd)
            await MainActor.run {
                slotOutput[c.slotId] = result.output
                slotValidated[c.slotId] = result.exitCode == 0
                slotValidating[c.slotId] = false
                // Parse "DATABASES_DISCOVERED: a,b,c" marker out of the script output.
                if let line = result.output
                    .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                    .first(where: { $0.hasPrefix("DATABASES_DISCOVERED:") }) {
                    let csv = line.dropFirst("DATABASES_DISCOVERED:".count)
                    let dbs = csv.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !dbs.isEmpty { slotDiscoveredDbs[c.slotId] = dbs }
                }
            }
        }
    }

    private func currentDatabasesCSV(_ c: ConnectionField) -> [String] {
        (plainValues[c.databaseKey] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func setDatabasesCSV(_ c: ConnectionField, _ dbs: [String]) {
        plainValues[c.databaseKey] = dbs.joined(separator: ", ")
        slotValidated[c.slotId] = false   // user changed selection → re-verify
    }

    private func toggleDatabaseInList(_ c: ConnectionField, _ db: String) {
        var current = currentDatabasesCSV(c)
        if let idx = current.firstIndex(of: db) {
            current.remove(at: idx)
        } else {
            current.append(db)
        }
        setDatabasesCSV(c, current)
    }

    private func providerColor(_ key: String?) -> Color {
        switch key {
        case "orange": return .orange
        case "purple": return DS.Color.purple
        case "blue":   return .blue
        case "green":  return .green
        case "red":    return .red
        case "gray":   return DS.Color.textPrimary
        default: return DS.Color.accent
        }
    }

    private func validationCard(_ v: TemplateValidation) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: validated ? "checkmark.seal.fill" : "checkmark.shield")
                    .foregroundStyle(validated ? DS.Color.success : DS.Color.accent)
                Text("Validation").font(DS.Typo.headline)
                Spacer()
                if validated {
                    Label("validated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DS.Color.success).font(DS.Typo.caption)
                }
            }
            Text(v.label).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
            HStack {
                Button { runValidation(v) } label: {
                    if validating {
                        HStack { ProgressView().controlSize(.small); Text("Running…") }
                    } else {
                        Label("Run validation", systemImage: "play.fill")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(validating || !fieldsFilled)
                if !fieldsFilled {
                    Text("Fill all fields above first")
                        .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
            }
            if !validationOutput.isEmpty {
                ScrollView {
                    Text(validationOutput)
                        .font(DS.Typo.monoSmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(DS.Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
                if validated {
                    Label(v.successHint, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DS.Color.success).font(DS.Typo.caption)
                } else {
                    Label("Validation failed. Fix the values above and try again.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Color.warning).font(DS.Typo.caption)
                }
            }
        }
        .designCard()
    }

    @ViewBuilder
    private var pluginsCard: some View {
        if !template.suggestedPluginIds.isEmpty {
            let missing = missingPlugins()
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(DS.Color.purple)
                    Text("Suggested plugins").font(DS.Typo.headline)
                }
                ForEach(template.suggestedPluginIds, id: \.self) { id in
                    HStack {
                        Image(systemName: missing.contains(id) ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(missing.contains(id) ? DS.Color.textTertiary : DS.Color.success)
                        Text(id).font(DS.Typo.monoSmall)
                        Spacer()
                        Text(missing.contains(id) ? "not installed" : "installed")
                            .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                if !missing.isEmpty {
                    Toggle("Auto-install missing plugins on create", isOn: $autoInstallPlugins)
                        .toggleStyle(.checkbox).font(DS.Typo.caption)
                }
            }
            .designCard()
        }
    }

    private var footer: some View {
        HStack {
            if let err = error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Color.danger).font(DS.Typo.caption)
            } else if requiresValidation && !validated {
                Label("Run validation before creating", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Color.warning).font(DS.Typo.caption)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SubtleTextButtonStyle())
            Button("Create agent") { create() }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .grayscale(canCreate ? 0 : 1)
                .opacity(canCreate ? 1.0 : 0.45)
                .help(canCreate
                      ? "Create (or replace) the agent and store secrets in Keychain"
                      : requiresValidation && !validated
                        ? "Run validation first — the agent can't be created until the token works"
                        : "Fill in all required fields")
        }
        .padding(DS.Space.l)
        .background(DS.Color.surface)
    }

    // MARK: - Helpers

    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(DS.Color.textTertiary)
            Text(LocalizedStringKey(markdown))
                .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func folderFieldRow(_ field: PlainVarField) -> some View {
        let project = state.projectsVM.currentProject
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label).font(DS.Typo.captionMedium)
                Spacer()
                Text(field.key).font(DS.Typo.monoSmall).foregroundStyle(DS.Color.textTertiary)
            }
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(DS.Color.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(DS.Typo.bodyMedium)
                    Text(project.path).font(DS.Typo.monoSmall).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Text("locked to current project")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Space.s)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(DS.Color.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .stroke(DS.Color.border, lineWidth: 1)
                    )
            )
            Text("Switch project in the sidebar to use a different folder. \(field.help)")
                .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private func fieldRow(
        _ label: String, key: String, help: String, isSecret: Bool,
        placeholder: String, binding: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(DS.Typo.captionMedium)
                Spacer()
                Text(key).font(DS.Typo.monoSmall).foregroundStyle(DS.Color.textTertiary)
            }
            if isSecret {
                SecureField(placeholder, text: binding)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typo.monoSmall)
            }
            Text(help).font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var fieldsFilled: Bool {
        for f in template.plainVarsToSetup where !f.isOptional && (plainValues[f.key]?.isEmpty ?? true) { return false }
        for f in template.secretsToSetup where !f.isOptional && (secretValues[f.key]?.isEmpty ?? true) { return false }
        // At least one secret must be filled if any are present.
        if !template.secretsToSetup.isEmpty {
            let anyFilled = template.secretsToSetup.contains { !(secretValues[$0.key]?.isEmpty ?? true) }
            if !anyFilled { return false }
        }
        // Connection slots: only visible required slots must be fully filled.
        for c in template.connections where !c.isOptional && visibleSlots.contains(c.slotId) {
            if connectionMissingFields(c).count > 0 { return false }
        }
        return true
    }

    /// Returns true if user typed anything into any field of this slot.
    private func slotHasInput(_ c: ConnectionField) -> Bool {
        let plainKeys = [c.aliasKey, c.schemeKey, c.hostKey, c.userKey, c.databaseKey]
        for k in plainKeys where !(plainValues[k]?.isEmpty ?? true) { return true }
        if !(secretValues[c.passwordKey]?.isEmpty ?? true) { return true }
        return false
    }

    /// Required fields per slot: alias, scheme, host, user, password, database.
    private func connectionMissingFields(_ c: ConnectionField) -> [String] {
        var missing: [String] = []
        if (plainValues[c.aliasKey]?.isEmpty ?? true)    { missing.append("alias") }
        if (plainValues[c.schemeKey]?.isEmpty ?? true)   { missing.append("scheme") }
        if (plainValues[c.hostKey]?.isEmpty ?? true)     { missing.append("host") }
        if (plainValues[c.userKey]?.isEmpty ?? true)     { missing.append("user") }
        if (secretValues[c.passwordKey]?.isEmpty ?? true) { missing.append("password") }
        if (plainValues[c.databaseKey]?.isEmpty ?? true) { missing.append("database") }
        return missing
    }

    private var requiresValidation: Bool { template.validation != nil }

    private var canCreate: Bool {
        guard !trimmedName.isEmpty, fieldsFilled else { return false }
        if requiresValidation && !validated { return false }
        // Each visible connection slot that is filled (or required) must have passed its own verify.
        for c in template.connections where visibleSlots.contains(c.slotId) {
            let filled = slotHasInput(c) || !c.isOptional
            if filled && (slotValidated[c.slotId] != true) { return false }
        }
        return true
    }

    private func missingPlugins() -> Set<String> {
        let enabled = Set(state.container.pluginRepository.loadAll().filter(\.isEnabled).map(\.id))
        return Set(template.suggestedPluginIds.filter { !enabled.contains($0) })
    }

    private func initializeIfNeeded() {
        guard !didInit else { return }
        didInit = true
        name = template.name
        let projectPath = state.projectsVM.currentProject.path
        for field in template.plainVarsToSetup {
            if field.isFolder {
                plainValues[field.key] = projectPath
            } else {
                plainValues[field.key] = field.defaultValue
            }
        }
        // Pre-fill the scheme picker on each slot so it isn't empty on first render.
        for c in template.connections {
            if plainValues[c.schemeKey] == nil || (plainValues[c.schemeKey]?.isEmpty ?? true) {
                plainValues[c.schemeKey] = c.schemeOptions.first ?? ""
            }
        }
        // Only show the first required slot initially — extras are added via "+".
        if let first = template.connections.first {
            visibleSlots = [first.slotId]
        }
    }

    /// Scrub for secrets: keep printable ASCII only. Drops zero-width Unicode, NBSP, smart quotes,
    /// control chars and other invisible noise from copy-paste — but preserves URL characters
    /// (`:`, `@`, `?`, `&`, …) so DSN-style secrets aren't mangled.
    private static func cleanSecret(_ s: String) -> String {
        String(s.unicodeScalars.filter { (0x21...0x7E).contains($0.value) }
            .map(Character.init))
    }

    private func substitute(_ raw: String) -> String {
        var r = raw
        let ws = CharacterSet.whitespacesAndNewlines
        // Plain vars: just trim whitespace (URL/email may contain ., @, /, : — don't strip those).
        for f in template.plainVarsToSetup {
            let v = (plainValues[f.key] ?? "").trimmingCharacters(in: ws)
            r = r.replacingOccurrences(of: "{\(f.key)}", with: v)
        }
        // Secrets: aggressive scrub — see cleanSecret.
        for f in template.secretsToSetup {
            let v = Self.cleanSecret((secretValues[f.key] ?? "").trimmingCharacters(in: ws))
            r = r.replacingOccurrences(of: "{\(f.key)}", with: v)
        }
        return r
    }

    private func runValidation(_ v: TemplateValidation) {
        validating = true
        validationOutput = "Running…"
        for field in template.plainVarsToSetup where field.isFolder {
            plainValues[field.key] = state.projectsVM.currentProject.path
        }
        let cmd = substitute(v.command)
        Task.detached {
            let result = await Self.runShell(cmd)
            await MainActor.run {
                self.validationOutput = result.output
                self.validated = result.exitCode == 0
                self.validating = false
            }
        }
    }

    // MARK: - Create

    private func create() {
        guard canCreate else { return }
        guard !postCreateRunning else { return }   // setup already running — ignore double-click
        // Clear any leftover error so a green path doesn't show stale red text.
        error = nil
        let trimmed = trimmedName
        // Lock folder fields to current project path at create-time.
        for field in template.plainVarsToSetup where field.isFolder {
            plainValues[field.key] = state.projectsVM.currentProject.path
        }
        do {
            // 1. Resolve bash patterns from preset labels.
            let presetsByLabel = Dictionary(uniqueKeysWithValues: BashPresets.all.map { ($0.label, $0) })
            var bashPatterns: [String] = []
            for label in template.bashPresetIds {
                if let p = presetsByLabel[label] {
                    bashPatterns.append(contentsOf: p.patterns)
                }
            }
            let tools = template.suggestedTools.map(\.rawValue)
                + bashPatterns.sorted().map { "Bash(\($0))" }

            // 2. Resolve skills.
            let chosenSkills = state.agentsVM.availableSkills.filter {
                template.suggestedSkillNames.contains($0.name)
            }

            // 3. Create agent file.
            let agentURL = try state.container.agentRepository.save(
                name: trimmed,
                description: template.description,
                model: template.model,
                tools: tools,
                systemPrompt: template.promptTemplate,
                skills: chosenSkills,
                overwrite: true
            )

            // 4. Persist plain vars and secrets — trim copy-paste whitespace/newlines.
            let ws = CharacterSet.whitespacesAndNewlines
            for f in template.plainVarsToSetup {
                let v = (plainValues[f.key] ?? "").trimmingCharacters(in: ws)
                guard !v.isEmpty else { continue }
                try? state.container.agentVariables.save(
                    key: f.key, value: v, isSecret: false, for: trimmed
                )
            }
            for f in template.secretsToSetup {
                let v = Self.cleanSecret((secretValues[f.key] ?? "").trimmingCharacters(in: ws))
                guard !v.isEmpty else { continue }
                try? state.container.agentVariables.save(
                    key: f.key, value: v, isSecret: true, for: trimmed
                )
            }

            // 4b. Persist connection-slot fields — only visible/used slots.
            for c in template.connections where visibleSlots.contains(c.slotId) {
                if c.isOptional && !slotHasInput(c) { continue }
                let plainKeys = [c.aliasKey, c.schemeKey, c.hostKey, c.userKey, c.databaseKey]
                for k in plainKeys {
                    let v = (plainValues[k] ?? "").trimmingCharacters(in: ws)
                    guard !v.isEmpty else { continue }
                    try? state.container.agentVariables.save(
                        key: k, value: v, isSecret: false, for: trimmed
                    )
                }
                let pw = Self.cleanSecret((secretValues[c.passwordKey] ?? "").trimmingCharacters(in: ws))
                if !pw.isEmpty {
                    try? state.container.agentVariables.save(
                        key: c.passwordKey, value: pw, isSecret: true, for: trimmed
                    )
                }
            }

            // 5. Auto-install missing plugins if opted in.
            if autoInstallPlugins {
                let byId = Dictionary(uniqueKeysWithValues:
                    state.container.pluginRepository.loadAll().map { ($0.id, $0) })
                for pluginId in template.suggestedPluginIds {
                    guard let plugin = byId[pluginId], !plugin.isEnabled else { continue }
                    try? state.container.pluginRepository.setEnabled(plugin, true)
                }
            }

            // 6. Optional post-create step (e.g. database schema introspection) — runs in the
            //    background so the sheet closes immediately and the agent appears in the sidebar.
            if let cmd = template.postCreateCommand {
                runPostCreate(cmd, agentURL: agentURL, agentName: trimmed)
            }
            state.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Run the template's post-create shell after the agent is saved. Stays in the sheet so the
    /// user sees progress; "Continue in background" lets them detach.
    private func runPostCreate(_ commandTemplate: String, agentURL: URL, agentName: String) {
        var cmd = substitute(commandTemplate)
        let agentDir = agentURL.deletingLastPathComponent().path
        cmd = cmd.replacingOccurrences(of: "{AGENT_NAME}", with: agentName)
        cmd = cmd.replacingOccurrences(of: "{AGENT_DIR}",  with: agentDir)

        // Also substitute every connection slot's keys — substitute() only walks plainVars/secrets
        // declared at top level, not ConnectionField keys.
        let ws = CharacterSet.whitespacesAndNewlines
        for c in template.connections {
            let plainKeys = [c.aliasKey, c.schemeKey, c.hostKey, c.userKey, c.databaseKey]
            for k in plainKeys {
                let v = (plainValues[k] ?? "").trimmingCharacters(in: ws)
                cmd = cmd.replacingOccurrences(of: "{\(k)}", with: v)
            }
            let pw = Self.cleanSecret((secretValues[c.passwordKey] ?? "").trimmingCharacters(in: ws))
            cmd = cmd.replacingOccurrences(of: "{\(c.passwordKey)}", with: pw)
        }

        postCreateRunning = true
        postCreateDone = false
        postCreateOutput = "Starting…\n"
        Task.detached {
            let result = await Self.runShell(cmd, timeoutSec: 300)
            await MainActor.run {
                postCreateOutput = result.output
                postCreateExitCode = result.exitCode
                postCreateRunning = false
                postCreateDone = true
            }
        }
    }

    // MARK: - Shell

    private struct ShellResult { let output: String; let exitCode: Int32 }

    private static func runShell(_ command: String, timeoutSec: Int = 30) async -> ShellResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ShellResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Stream output incrementally so we don't lose tail buffer on SIGKILL.
            let bufferLock = NSLock()
            var collected = Data()
            pipe.fileHandleForReading.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty { return }
                bufferLock.lock(); collected.append(chunk); bufferLock.unlock()
            }

            do { try process.run() } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: ShellResult(output: error.localizedDescription, exitCode: -1))
                return
            }

            let pid = process.processIdentifier
            let timeoutFlag = NSLock()
            var didTimeout = false
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSec)) {
                if process.isRunning {
                    timeoutFlag.lock(); didTimeout = true; timeoutFlag.unlock()
                    process.terminate()
                    kill(pid, SIGKILL)
                    kill(-pid, SIGKILL)
                }
            }

            DispatchQueue.global().async {
                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                // Drain anything still buffered after handler was detached.
                let tail = pipe.fileHandleForReading.availableData
                if !tail.isEmpty {
                    bufferLock.lock(); collected.append(tail); bufferLock.unlock()
                }
                bufferLock.lock()
                var out = String(data: collected, encoding: .utf8) ?? ""
                bufferLock.unlock()
                let code = process.terminationStatus

                timeoutFlag.lock()
                let killed = didTimeout
                timeoutFlag.unlock()
                if killed {
                    if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                    out += "✗ Hit \(timeoutSec)s wall-clock timeout. Likely causes:\n"
                    out += "  • Port closed/wrong (Yandex MDB Postgres uses 6432, not 5432)\n"
                    out += "  • Firewall/VPN blocking outbound\n"
                    out += "  • SSL handshake hung (Yandex MDB needs CA: ~/.postgresql/root.crt)\n"
                }
                cont.resume(returning: ShellResult(output: out, exitCode: killed ? -1 : code))
            }
        }
    }
}
