import SwiftUI

/// v3 memory UI for one agent: searchable list of notes (facts/rules/playbooks/
/// sessions/vars) backed by the SQLite store, plus a graph view of their links.
/// Replaces the file-based v2 card — no more digging through .md files.
struct AgentMemoryV3Card: View {
    let agentName: String

    @State private var store: MemoryStore?
    @State private var notes: [MemoryNote] = []
    @State private var edges: [MemoryEdge] = []
    @State private var query: String = ""
    @State private var kindFilter: MemoryNote.Kind?
    @State private var mode: Mode = .list
    @State private var expanded: Set<String> = []
    @State private var error: String?
    @State private var v2Count: Int = 0
    @State private var migrationNote: String?

    enum Mode: String, CaseIterable { case list, graph }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            header

            if let error {
                Text(error).font(DS.Typo.caption).foregroundStyle(DS.Color.danger)
            }
            if v2Count > 0 { migrationBanner }
            if let migrationNote {
                Text(migrationNote).font(DS.Typo.caption).foregroundStyle(DS.Color.success)
            }

            if mode == .list {
                searchBar
                kindFilterRow
                if filteredNotes.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredNotes) { note in
                        noteRow(note)
                    }
                }
            } else {
                MemoryGraphView(notes: notes, edges: edges, onSelect: { id in
                    mode = .list
                    expanded = [id]
                    query = ""
                    kindFilter = nil
                })
                .frame(height: 360)
            }
        }
        .designCard()
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            DesignSectionHeader(title: "Память", icon: "brain.head.profile")
            Spacer()
            Text("\(notes.count)")
                .font(DS.Typo.micro).foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(DS.Color.surfaceElevated).clipShape(Capsule())
            Picker("", selection: $mode) {
                Image(systemName: "list.bullet").tag(Mode.list)
                Image(systemName: "point.3.connected.trianglepath.dotted").tag(Mode.graph)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
            .labelsHidden()
            Button {
                load()
            } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.plain)
            .help("Перечитать память")
        }
    }

    private var migrationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill").foregroundStyle(DS.Color.accent)
            Text("Найдена старая память v2 (\(v2Count) файл\(v2Count == 1 ? "" : "а/ов")).")
                .font(DS.Typo.caption)
            Spacer()
            Button("Импортировать") { migrate() }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.Color.accent.opacity(0.08)))
    }

    // MARK: - List

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.Color.textTertiary)
            TextField("Поиск по памяти…", text: $query)
                .textFieldStyle(.plain)
                .onSubmit(runSearch)
            if !query.isEmpty {
                Button { query = ""; load() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Color.textTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.s).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.Color.surfaceElevated))
        .onChange(of: query) { _, q in if q.isEmpty { load() } }
    }

    private var kindFilterRow: some View {
        HStack(spacing: 6) {
            chip(title: "Все", active: kindFilter == nil) { kindFilter = nil }
            ForEach(MemoryNote.Kind.allCases, id: \.rawValue) { k in
                chip(title: kindLabel(k), active: kindFilter == k) {
                    kindFilter = (kindFilter == k) ? nil : k
                }
            }
        }
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.Typo.micro)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(active ? DS.Color.accent.opacity(0.18) : DS.Color.surfaceElevated))
                .foregroundStyle(active ? DS.Color.accent : DS.Color.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func noteRow(_ note: MemoryNote) -> some View {
        let isOpen = expanded.contains(note.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                kindBadge(note.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).font(DS.Typo.bodyMedium)
                    if isOpen {
                        Text(note.body).font(DS.Typo.caption).foregroundStyle(DS.Color.textSecondary)
                            .textSelection(.enabled)
                        if !note.tags.isEmpty {
                            Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                                .font(DS.Typo.micro).foregroundStyle(DS.Color.textTertiary)
                        }
                        let neighbors = (try? store?.neighbors(of: note.id)) ?? []
                        if !neighbors.isEmpty {
                            Text("Связано: " + neighbors.map(\.title).joined(separator: " · "))
                                .font(DS.Typo.micro).foregroundStyle(DS.Color.purple)
                        }
                    } else {
                        Text(note.body).font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isOpen {
                    Button(role: .destructive) { delete(note) } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(DS.Color.danger)
                }
            }
        }
        .padding(.horizontal, DS.Space.s).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s)
            .fill(isOpen ? DS.Color.accent.opacity(0.06) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            if isOpen { expanded.remove(note.id) } else { expanded.insert(note.id) }
        }
    }

    private var emptyState: some View {
        Text(query.isEmpty
             ? "Память пуста. Агент сам наполнит её через memory_write по мере работы."
             : "Ничего не найдено по «\(query)».")
            .font(DS.Typo.caption).foregroundStyle(DS.Color.textTertiary)
            .padding(.vertical, DS.Space.s)
    }

    // MARK: - Badges / labels

    private func kindBadge(_ kind: MemoryNote.Kind) -> some View {
        let (icon, color) = kindStyle(kind)
        return Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.15)))
    }

    private func kindStyle(_ kind: MemoryNote.Kind) -> (String, Color) {
        switch kind {
        case .fact: return ("info.circle.fill", DS.Color.accent)
        case .rule: return ("checkmark.shield.fill", DS.Color.success)
        case .playbook: return ("list.number", DS.Color.purple)
        case .session: return ("clock.fill", DS.Color.textSecondary)
        case .variable: return ("curlybraces", DS.Color.teal)
        }
    }

    private func kindLabel(_ kind: MemoryNote.Kind) -> String {
        switch kind {
        case .fact: return "Факты"
        case .rule: return "Правила"
        case .playbook: return "Playbooks"
        case .session: return "Сессии"
        case .variable: return "Переменные"
        }
    }

    private var filteredNotes: [MemoryNote] {
        guard let kindFilter else { return notes }
        return notes.filter { $0.kind == kindFilter }
    }

    // MARK: - Data

    private func load() {
        do {
            let s = try store ?? MemoryStore(path: AgentPaths.current.memoryDBFile)
            store = s
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                notes = try s.allNotes(agent: agentName)
            } else {
                notes = try s.search(query, agent: agentName, limit: 50)
            }
            edges = try s.allEdges()
            v2Count = MemoryMigration.sources(agent: agentName, paths: .current).count
            error = nil
        } catch {
            self.error = "Не удалось открыть память: \(error.localizedDescription)"
        }
    }

    private func migrate() {
        do {
            let s = try store ?? MemoryStore(path: AgentPaths.current.memoryDBFile)
            store = s
            let n = try MemoryMigration.migrate(agent: agentName, store: s, paths: .current)
            migrationNote = "Импортировано заметок: \(n). Старые файлы перенесены в _v2_backup/."
            load()
        } catch {
            self.error = "Импорт не удался: \(error.localizedDescription)"
        }
    }

    private func runSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return load() }
        load()
    }

    private func delete(_ note: MemoryNote) {
        guard let store else { return }
        try? store.delete(id: note.id)
        expanded.remove(note.id)
        load()
    }
}
