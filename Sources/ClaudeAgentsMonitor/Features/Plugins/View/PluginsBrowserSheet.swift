import SwiftUI
import AppKit

struct PluginsBrowserSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var plugins: [ClaudePlugin] = []
    @State private var search: String = ""
    @State private var selectedCategory: String = "all"
    @State private var showOnlyEnabled: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            filters
            Divider()
            list
        }
        .frame(width: 880, height: 720)
        .background(DS.Color.bg)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(LinearGradient(
                        colors: [DS.Color.purple, DS.Color.accent],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 36, height: 36)
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Plugins").font(DS.Typo.title)
                Text("\(plugins.count) plugins · \(plugins.filter(\.isEnabled).count) enabled")
                    .font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            Button("Reload") { reload() }
                .buttonStyle(OutlineButtonStyle())
            Button("Done") { dismiss() }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(DS.Space.l)
    }

    private var filters: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.Color.textTertiary)
            TextField("Search plugins…", text: $search)
                .textFieldStyle(.plain)
                .font(DS.Typo.body)
            Spacer()
            Picker("Category", selection: $selectedCategory) {
                Text("All categories").tag("all")
                ForEach(state.container.pluginRepository.loadAll().map(\.displayCategory).reduce(into: Set<String>()) { $0.insert($1) }.sorted(), id: \.self) { cat in
                    Text(cat.capitalized).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
            Toggle(isOn: $showOnlyEnabled) {
                Text("Enabled only").font(DS.Typo.caption)
            }
            .toggleStyle(.checkbox)
        }
        .padding(DS.Space.m)
    }

    private var filtered: [ClaudePlugin] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return plugins.filter { p in
            if showOnlyEnabled && !p.isEnabled { return false }
            if selectedCategory != "all" && p.displayCategory != selectedCategory { return false }
            if q.isEmpty { return true }
            return p.name.lowercased().contains(q)
                || p.description.lowercased().contains(q)
                || (p.authorName?.lowercased().contains(q) ?? false)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.s) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Color.danger).font(DS.Typo.caption)
                        .padding(DS.Space.m)
                }
                if filtered.isEmpty {
                    EmptyState(
                        icon: "puzzlepiece.extension",
                        title: "Nothing found",
                        subtitle: "Reset filters or change your query."
                    )
                    .frame(maxWidth: .infinity)
                }
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, plugin in
                    pluginRow(plugin).staggeredAppear(idx, delayPer: 0.015)
                }
            }
            .padding(DS.Space.m)
        }
    }

    private func pluginRow(_ plugin: ClaudePlugin) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(categoryColor(plugin.displayCategory).opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: categoryIcon(plugin.displayCategory))
                    .foregroundStyle(categoryColor(plugin.displayCategory))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(DS.Typo.bodyMedium)
                    StatusBadge(text: plugin.displayCategory, color: categoryColor(plugin.displayCategory))
                    if !plugin.isLocallyAvailable {
                        StatusBadge(text: "remote", color: DS.Color.textTertiary)
                            .help("Will be downloaded on first enable")
                    }
                    if let author = plugin.authorName {
                        Text("by \(author)")
                            .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                Text(plugin.description)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(3)
                if let homepage = plugin.homepage, let url = URL(string: homepage) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "link")
                            Text(URL(string: homepage)?.host ?? homepage)
                        }
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            installButton(for: plugin)
        }
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .fill(plugin.isEnabled ? DS.Color.success.opacity(0.05) : DS.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m)
                        .stroke(plugin.isEnabled ? DS.Color.success.opacity(0.4) : DS.Color.border, lineWidth: 1)
                )
        )
    }

    private func installButton(for plugin: ClaudePlugin) -> some View {
        Button {
            toggle(plugin)
        } label: {
            if plugin.isEnabled {
                Label("Enabled", systemImage: "checkmark.circle.fill")
            } else {
                Label("Enable", systemImage: "plus.circle")
            }
        }
        .buttonStyle(plugin.isEnabled
                     ? AnyButtonStyle(GhostButtonStyle(tint: DS.Color.success))
                     : AnyButtonStyle(PressableButtonStyle()))
        .help(plugin.isEnabled
              ? "Disable — uncheck in settings.json"
              : (plugin.isLocallyAvailable
                 ? "Enable — adds \(plugin.id) to settings.json"
                 : "Enable — will be downloaded on next Claude Code launch"))
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "design": return DS.Color.purple
        case "development": return DS.Color.accent
        case "security": return DS.Color.danger
        case "testing": return DS.Color.warning
        case "deployment": return DS.Color.teal
        case "monitoring": return DS.Color.info
        case "productivity": return DS.Color.success
        case "automation": return DS.Color.warning
        case "database": return DS.Color.teal
        case "math": return DS.Color.purple
        case "learning": return DS.Color.info
        case "location": return DS.Color.success
        default: return DS.Color.textSecondary
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "design": return "paintpalette.fill"
        case "development": return "hammer.fill"
        case "security": return "lock.shield.fill"
        case "testing": return "checkmark.shield.fill"
        case "deployment": return "shippingbox.fill"
        case "monitoring": return "waveform.path.ecg"
        case "productivity": return "bolt.fill"
        case "automation": return "gearshape.2.fill"
        case "database": return "cylinder.split.1x2.fill"
        case "math": return "function"
        case "learning": return "graduationcap.fill"
        case "location": return "location.fill"
        default: return "puzzlepiece.extension.fill"
        }
    }

    private func reload() {
        plugins = state.container.pluginRepository.loadAll()
    }

    private func toggle(_ plugin: ClaudePlugin) {
        do {
            try state.container.pluginRepository.setEnabled(plugin, !plugin.isEnabled)
            reload()
            // Refresh app state so new plugin skills appear in agent form
            state.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Type-erased button style for conditional usage.
private struct AnyButtonStyle: ButtonStyle {
    let _make: (ButtonStyleConfiguration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        self._make = { conf in AnyView(style.makeBody(configuration: conf)) }
    }
    func makeBody(configuration: Configuration) -> some View {
        _make(configuration)
    }
}
