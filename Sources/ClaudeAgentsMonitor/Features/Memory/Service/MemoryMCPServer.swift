import Foundation

/// Minimal MCP (Model Context Protocol) server over stdio, exposing the three
/// memory tools to a Claude Code agent: `memory_search`, `memory_write`, `memory_link`.
///
/// Launched as a subprocess by the `claude` CLI via a `.claude.json` entry:
///   { "command": "<path>/ClaudeAgentsMonitor",
///     "args": ["--mcp-serve", "--db", "<...>/memory.db", "--agent", "<name>"] }
///
/// Transport: newline-delimited JSON-RPC 2.0 on stdin/stdout (MCP stdio transport).
enum MemoryMCPServer {
    static let protocolVersion = "2024-11-05"

    static func run() {
        let args = CommandLine.arguments
        let dbPath = value(of: "--db", in: args)
        let defaultAgent = value(of: "--agent", in: args) ?? ""

        guard let dbPath else {
            log("missing --db <path>")
            exit(1)
        }

        let store: MemoryStore
        do {
            store = try MemoryStore(path: URL(fileURLWithPath: dbPath))
        } catch {
            log("failed to open db: \(error)")
            exit(1)
        }

        log("memory MCP server up (db=\(dbPath), agent=\(defaultAgent.isEmpty ? "<shared>" : defaultAgent))")

        // Line-delimited JSON-RPC read loop.
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            handle(msg, store: store, defaultAgent: defaultAgent)
        }
    }

    // MARK: - Dispatch

    private static func handle(_ msg: [String: Any], store: MemoryStore, defaultAgent: String) {
        let method = msg["method"] as? String ?? ""
        let id = msg["id"]                       // absent for notifications
        let params = msg["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "cam-memory", "version": "3.0.0"],
            ])

        case "notifications/initialized", "notifications/cancelled":
            break // notifications: no response

        case "tools/list":
            respond(id: id, result: ["tools": toolSchemas])

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let toolArgs = params["arguments"] as? [String: Any] ?? [:]
            callTool(name, args: toolArgs, id: id, store: store, defaultAgent: defaultAgent)

        case "ping":
            respond(id: id, result: [:])

        default:
            if id != nil {
                respondError(id: id, code: -32601, message: "method not found: \(method)")
            }
        }
    }

    // MARK: - Tools

    private static func callTool(_ name: String, args: [String: Any], id: Any?, store: MemoryStore, defaultAgent: String) {
        do {
            switch name {
            case "memory_search":
                let query = args["query"] as? String ?? ""
                let limit = args["limit"] as? Int ?? 5
                let agent = args["agent"] as? String ?? defaultAgent
                let hits = try store.search(query, agent: agent, limit: limit)
                toolResult(id: id, text: renderNotes(hits, emptyMsg: "Ничего не найдено в памяти."))

            case "memory_write":
                guard let title = args["title"] as? String, !title.isEmpty,
                      let body = args["body"] as? String else {
                    return toolError(id: id, "memory_write requires 'title' and 'body'")
                }
                let kind = MemoryNote.Kind(rawValue: args["kind"] as? String ?? "fact") ?? .fact
                let tags = args["tags"] as? [String] ?? []
                let agent = args["agent"] as? String ?? defaultAgent

                // Dedup: update an existing active note with the same title for this agent.
                let existing = try store.allNotes(agent: agent, includeShared: false)
                    .first { $0.title == title && $0.kind == kind }
                var note = existing ?? MemoryNote(agent: agent, kind: kind, title: title, body: body, tags: tags)
                note.body = body
                note.tags = tags
                note.kind = kind
                try store.save(note)

                if let links = args["links"] as? [String] {
                    for dst in links {
                        try? store.link(MemoryEdge(src: note.id, dst: dst, rel: .relates))
                    }
                }
                toolResult(id: id, text: "Сохранено [\(kind.rawValue)] «\(title)» (id=\(note.id))")

            case "memory_link":
                guard let src = args["src"] as? String, let dst = args["dst"] as? String else {
                    return toolError(id: id, "memory_link requires 'src' and 'dst'")
                }
                let rel = MemoryEdge.Relation(rawValue: args["rel"] as? String ?? "relates") ?? .relates
                try store.link(MemoryEdge(src: src, dst: dst, rel: rel))
                toolResult(id: id, text: "Связано \(src) -[\(rel.rawValue)]-> \(dst)")

            default:
                toolError(id: id, "unknown tool: \(name)")
            }
        } catch {
            toolError(id: id, "tool error: \(error)")
        }
    }

    private static func renderNotes(_ notes: [MemoryNote], emptyMsg: String) -> String {
        guard !notes.isEmpty else { return emptyMsg }
        return notes.map { n in
            let tags = n.tags.isEmpty ? "" : " [" + n.tags.joined(separator: ", ") + "]"
            return "• (\(n.kind.rawValue), id=\(n.id))\(tags) \(n.title)\n  \(n.body)"
        }.joined(separator: "\n")
    }

    private static let toolSchemas: [[String: Any]] = [
        [
            "name": "memory_search",
            "description": "Найти релевантные заметки памяти (факты, правила, итоги прошлых сессий). Вызывай в начале задачи. Возвращает топ-N, а не всю память.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Поисковый запрос по сути задачи"],
                    "limit": ["type": "integer", "description": "Сколько заметок вернуть (по умолчанию 5)"],
                ],
                "required": ["query"],
            ],
        ],
        [
            "name": "memory_write",
            "description": "Сохранить/обновить заметку в памяти. Вызывай в конце задачи для новых фактов, правил, процедур и итогов сессии. Заметка с тем же title обновляется, а не дублируется.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "kind": ["type": "string", "enum": ["fact", "rule", "playbook", "session", "var"], "description": "Вид заметки"],
                    "title": ["type": "string", "description": "Короткий заголовок"],
                    "body": ["type": "string", "description": "Содержимое"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "links": ["type": "array", "items": ["type": "string"], "description": "id заметок для связи"],
                ],
                "required": ["title", "body"],
            ],
        ],
        [
            "name": "memory_link",
            "description": "Связать две заметки (строит граф памяти).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "src": ["type": "string"],
                    "dst": ["type": "string"],
                    "rel": ["type": "string", "enum": ["relates", "causes", "supersedes", "example_of"]],
                ],
                "required": ["src", "dst"],
            ],
        ],
    ]

    // MARK: - JSON-RPC plumbing

    private static func respond(id: Any?, result: [String: Any]) {
        guard let id else { return }
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func respondError(id: Any?, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private static func toolResult(id: Any?, text: String) {
        respond(id: id, result: ["content": [["type": "text", "text": text]]])
    }

    private static func toolError(id: Any?, _ text: String) {
        respond(id: id, result: ["content": [["type": "text", "text": text]], "isError": true])
    }

    private static func write(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              var s = String(data: data, encoding: .utf8) else { return }
        s += "\n"
        FileHandle.standardOutput.write(Data(s.utf8))
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Logs go to stderr — stdout is reserved for the JSON-RPC channel.
    private static func log(_ s: String) {
        FileHandle.standardError.write(Data(("[cam-memory] " + s + "\n").utf8))
    }
}
