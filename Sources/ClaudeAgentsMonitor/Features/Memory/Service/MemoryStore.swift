import Foundation
import GRDB

/// SQLite-backed agent memory: notes + typed edges (the graph) + FTS5 search.
/// One database file per project (`<project>/.claude/agents/memory/memory.db`).
///
/// This is the source of truth for both the agent (via the MCP memory tools)
/// and the CAM UI (list, search, graph view).
final class MemoryStore {
    let dbQueue: DatabaseQueue

    /// Open (creating if needed) the memory database at the given file URL.
    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        dbQueue = try DatabaseQueue(path: path.path)
        try Self.migrator.migrate(dbQueue)
    }

    /// In-memory store — for tests / previews.
    init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v3-initial") { db in
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()
                t.column("agent", .text).notNull().defaults(to: "")
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("tags", .text).notNull().defaults(to: "[]")
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("last_used_at", .integer)
                t.column("use_count", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "active")
            }
            try db.create(indexOn: "notes", columns: ["agent"])
            try db.create(indexOn: "notes", columns: ["kind"])
            try db.create(indexOn: "notes", columns: ["status"])

            try db.create(table: "edges") { t in
                t.column("src", .text).notNull()
                    .references("notes", onDelete: .cascade)
                t.column("dst", .text).notNull()
                    .references("notes", onDelete: .cascade)
                t.column("rel", .text).notNull()
                t.primaryKey(["src", "dst", "rel"])
            }
            try db.create(indexOn: "edges", columns: ["dst"]) // backlinks

            // FTS5 mirror of notes, kept in sync by triggers.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE notes_fts USING fts5(
                    title, body, tags,
                    content='notes', content_rowid='rowid'
                );
                """)
            try db.execute(sql: """
                CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
                    INSERT INTO notes_fts(rowid, title, body, tags)
                    VALUES (new.rowid, new.title, new.body, new.tags);
                END;
                """)
            try db.execute(sql: """
                CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
                    INSERT INTO notes_fts(notes_fts, rowid, title, body, tags)
                    VALUES ('delete', old.rowid, old.title, old.body, old.tags);
                END;
                """)
            try db.execute(sql: """
                CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
                    INSERT INTO notes_fts(notes_fts, rowid, title, body, tags)
                    VALUES ('delete', old.rowid, old.title, old.body, old.tags);
                    INSERT INTO notes_fts(rowid, title, body, tags)
                    VALUES (new.rowid, new.title, new.body, new.tags);
                END;
                """)
        }

        return m
    }

    // MARK: - CRUD

    /// Insert or replace a note.
    func save(_ note: MemoryNote) throws {
        try dbQueue.write { db in
            var n = note
            n.updatedAt = Date()
            try n.save(db)
        }
    }

    func note(id: String) throws -> MemoryNote? {
        try dbQueue.read { db in try MemoryNote.fetchOne(db, key: id) }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in try MemoryNote.deleteOne(db, key: id) }
    }

    /// All active notes for an agent (plus shared `agent=""`), newest first.
    func allNotes(agent: String, includeShared: Bool = true) throws -> [MemoryNote] {
        try dbQueue.read { db in
            var sql = "SELECT * FROM notes WHERE status = 'active' AND (agent = ?"
            let args: [DatabaseValueConvertible] = [agent]
            if includeShared {
                sql += " OR agent = ''"
            }
            sql += ") ORDER BY updated_at DESC"
            return try MemoryNote.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    func archive(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE notes SET status = 'archived', updated_at = ? WHERE id = ?",
                arguments: [MemoryNote.millis(from: Date()), id]
            )
        }
    }

    // MARK: - Search (lexical RAG)

    /// Full-text search ranked by relevance, recency, and use count.
    /// Bumps `last_used_at` / `use_count` on the returned notes (retrieval feedback).
    func search(_ query: String, agent: String, limit: Int = 5) throws -> [MemoryNote] {
        let match = Self.ftsQuery(from: query)
        guard !match.isEmpty else { return [] }

        let notes: [MemoryNote] = try dbQueue.read { db in
            // bm25() returns lower = better; combine with light recency/use boosts.
            let sql = """
                SELECT n.*
                FROM notes_fts f
                JOIN notes n ON n.rowid = f.rowid
                WHERE notes_fts MATCH ?
                  AND n.status = 'active'
                  AND (n.agent = ? OR n.agent = '')
                ORDER BY bm25(notes_fts) - (n.use_count * 0.1) ASC
                LIMIT ?
                """
            return try MemoryNote.fetchAll(
                db, sql: sql,
                arguments: [match, agent, limit]
            )
        }

        try bumpUsage(ids: notes.map(\.id))
        return notes
    }

    private func bumpUsage(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let now = MemoryNote.millis(from: Date())
            try db.execute(
                sql: "UPDATE notes SET use_count = use_count + 1, last_used_at = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([now] + ids)
            )
        }
    }

    /// Turn free text into a safe FTS5 prefix-OR query: `auth* OR token* OR review*`.
    static func ftsQuery(from text: String) -> String {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard !tokens.isEmpty else { return "" }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " OR ")
    }

    // MARK: - Edges (graph)

    func link(_ edge: MemoryEdge) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO edges (src, dst, rel) VALUES (?, ?, ?)",
                arguments: [edge.src, edge.dst, edge.rel.rawValue]
            )
        }
    }

    func unlink(_ edge: MemoryEdge) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM edges WHERE src = ? AND dst = ? AND rel = ?",
                arguments: [edge.src, edge.dst, edge.rel.rawValue]
            )
        }
    }

    func allEdges() throws -> [MemoryEdge] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT src, dst, rel FROM edges").map {
                MemoryEdge(
                    src: $0["src"],
                    dst: $0["dst"],
                    rel: MemoryEdge.Relation(rawValue: $0["rel"]) ?? .relates
                )
            }
        }
    }

    // MARK: - Variables (mirror of plain vars, for search)

    /// Stable id so a variable note upserts in place (one note per agent+key).
    static func varID(agent: String, key: String) -> String { "var_\(agent)_\(key)" }

    /// Mirror a non-secret variable into memory as a `var` note so it surfaces in search.
    func upsertVariable(agent: String, key: String, value: String) throws {
        let id = Self.varID(agent: agent, key: key)
        let createdAt = (try? note(id: id))?.createdAt ?? Date()
        try save(MemoryNote(id: id, agent: agent, kind: .variable,
                            title: key, body: value, tags: ["var"], createdAt: createdAt))
    }

    func deleteVariable(agent: String, key: String) throws {
        try delete(id: Self.varID(agent: agent, key: key))
    }

    /// Notes directly linked to `id` (either direction).
    func neighbors(of id: String) throws -> [MemoryNote] {
        try dbQueue.read { db in
            try MemoryNote.fetchAll(db, sql: """
                SELECT * FROM notes WHERE id IN (
                    SELECT dst FROM edges WHERE src = ?
                    UNION
                    SELECT src FROM edges WHERE dst = ?
                ) AND status = 'active'
                """, arguments: [id, id])
        }
    }
}
