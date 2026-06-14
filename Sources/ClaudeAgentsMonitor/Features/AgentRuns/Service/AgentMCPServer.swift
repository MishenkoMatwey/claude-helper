import Foundation

/// MCP server (`--agents-serve --project <root>`) giving the orchestrator
/// resumable agent sessions: `agent_run` starts an agent and remembers its
/// claude session; `agent_continue` resumes that SAME session so the agent
/// keeps its loaded project context (no cold re-read). `agent_list` shows runs.
enum AgentMCPServer {
    static let protocolVersion = "2024-11-05"

    static func run() {
        let args = CommandLine.arguments
        let projectPath = value(of: "--project", in: args)
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let projectURL = URL(fileURLWithPath: projectPath)
        let store = AgentRunStore(path: projectURL
            .appendingPathComponent(".claude/agents/memory/agent-runs.json"))

        log("agents MCP server up (project=\(projectPath))")

        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            handle(msg, store: store, cwd: projectURL)
        }
    }

    private static func handle(_ msg: [String: Any], store: AgentRunStore, cwd: URL) {
        let method = msg["method"] as? String ?? ""
        let id = msg["id"]
        let params = msg["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "cam-agents", "version": "1.0.0"],
            ])
        case "notifications/initialized", "notifications/cancelled":
            break
        case "tools/list":
            respond(id: id, result: ["tools": toolSchemas])
        case "tools/call":
            callTool(params["name"] as? String ?? "",
                     args: params["arguments"] as? [String: Any] ?? [:],
                     id: id, store: store, cwd: cwd)
        case "ping":
            respond(id: id, result: [:])
        default:
            if id != nil { respondError(id: id, code: -32601, message: "method not found: \(method)") }
        }
    }

    private static func callTool(_ name: String, args: [String: Any], id: Any?, store: AgentRunStore, cwd: URL) {
        switch name {
        case "agent_run":
            guard let agent = args["agent"] as? String, !agent.isEmpty,
                  let task = args["task"] as? String else {
                return toolError(id: id, "agent_run requires 'agent' and 'task'")
            }
            let bg = (args["background"] as? Bool) ?? false
            execute(agent: agent, task: task, resume: nil, runId: nil, background: bg,
                    id: id, store: store, cwd: cwd)

        case "agent_continue":
            let task = args["task"] as? String ?? ""
            guard !task.isEmpty else { return toolError(id: id, "agent_continue requires 'task'") }
            let run: AgentRun?
            if let runId = args["runId"] as? String { run = store.get(runId) }
            else if let agent = args["agent"] as? String { run = store.latest(forAgent: agent) }
            else { run = nil }
            guard let run else {
                return toolError(id: id, "no run found — pass a valid runId or agent name (use agent_list)")
            }
            let bg = (args["background"] as? Bool) ?? false
            execute(agent: run.agent, task: task, resume: run.sessionId, runId: run.id, background: bg,
                    id: id, store: store, cwd: cwd)

        case "agent_list":
            let runs = store.reconcileRunning().prefix(20)
            let text = runs.isEmpty
                ? "Нет запущенных/недавних агентов."
                : runs.map { "• \($0.id) [\($0.agent)] \($0.status)\($0.background ? " (фон)" : "") — \($0.lastTask.prefix(50))" }.joined(separator: "\n")
            toolResult(id: id, text: text)

        case "agent_status":
            guard let runId = args["runId"] as? String, let run = store.reconcileRunning().first(where: { $0.id == runId }) else {
                return toolError(id: id, "agent_status requires a valid 'runId' (use agent_list)")
            }
            let tail = store.tailLog(runId)
            toolResult(id: id, text: "[\(run.agent)] \(run.status)\n\(tail.isEmpty ? "(нет вывода)" : tail)")

        case "agent_stop":
            guard let runId = args["runId"] as? String, store.get(runId) != nil else {
                return toolError(id: id, "agent_stop requires a valid 'runId' (use agent_list)")
            }
            store.stop(runId)
            toolResult(id: id, text: "Остановлен \(runId).")

        default:
            toolError(id: id, "unknown tool: \(name)")
        }
    }

    /// Launch (or resume) the agent. Foreground: blocks, returns output. Background:
    /// returns immediately with a runId; monitor via agent_status, stop via agent_stop.
    private static func execute(agent: String, task: String, resume: String?, runId: String?,
                                background: Bool, id: Any?, store: AgentRunStore, cwd: URL) {
        let rid = runId ?? AgentRunStore.newRunID()

        if background {
            do {
                let proc = try AgentRunner.startBackground(
                    agent: agent, task: task, resumeSession: resume, cwd: cwd, logURL: store.logURL(rid))
                store.upsert(AgentRun(id: rid, agent: agent, sessionId: resume, lastTask: task,
                                      status: "running", updatedAtMillis: 0,
                                      pid: proc.processIdentifier, background: true))
                toolResult(id: id, text: "▶ \(agent) запущен в фоне. runId=\(rid). "
                    + "Следи: agent_status(runId=\"\(rid)\"); останови: agent_stop(runId=\"\(rid)\").")
            } catch {
                store.upsert(AgentRun(id: rid, agent: agent, sessionId: resume, lastTask: task,
                                      status: "failed", updatedAtMillis: 0, background: true))
                toolError(id: id, "background start failed: \(error.localizedDescription)")
            }
            return
        }

        // Foreground (blocking).
        store.upsert(AgentRun(id: rid, agent: agent, sessionId: resume,
                              lastTask: task, status: "running", updatedAtMillis: 0))
        do {
            let r = try AgentRunner.run(agent: agent, task: task, resumeSession: resume, cwd: cwd)
            store.upsert(AgentRun(id: rid, agent: agent, sessionId: r.sessionId ?? resume,
                                  lastTask: task, status: r.isError ? "failed" : "done", updatedAtMillis: 0))
            let hint = resume == nil
                ? "\n\n[runId=\(rid) — чтобы продолжить ЭТОГО агента без перечитывания проекта, вызови agent_continue с этим runId]"
                : "\n\n[продолжено в сессии runId=\(rid)]"
            toolResult(id: id, text: r.text + hint, isError: r.isError)
        } catch {
            store.upsert(AgentRun(id: rid, agent: agent, sessionId: resume,
                                  lastTask: task, status: "failed", updatedAtMillis: 0))
            toolError(id: id, "agent run failed: \(error.localizedDescription)")
        }
    }

    private static let toolSchemas: [[String: Any]] = [
        [
            "name": "agent_run",
            "description": "Запустить агента над задачей в НОВОЙ сессии. Возвращает результат и runId. ВАЖНО: для повторных правок тем же агентом используй agent_continue с этим runId — не запускай agent_run заново (иначе агент перечитает весь проект с нуля = медленно). background:true — запустить в фоне (не блокировать), следить через agent_status, останавливать agent_stop.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "agent": ["type": "string", "description": "Имя агента (как в AGENTS)"],
                    "task": ["type": "string", "description": "Полная задача с контекстом"],
                    "background": ["type": "boolean", "description": "true = запустить в фоне, не дожидаясь результата"],
                ],
                "required": ["agent", "task"],
            ],
        ],
        [
            "name": "agent_continue",
            "description": "Продолжить РАНЕЕ запущенного агента в его же сессии — проект уже загружен, без перечитывания (быстро). Используй для правок/доработок ('подправь', 'теперь сделай ещё'). Укажи runId (из agent_run/agent_list) ИЛИ имя agent (возьмётся последняя сессия). background:true — в фоне.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "runId": ["type": "string", "description": "runId из agent_run или agent_list"],
                    "agent": ["type": "string", "description": "Имя агента (fallback, если runId неизвестен — берётся последняя сессия)"],
                    "task": ["type": "string", "description": "Что доработать/исправить"],
                    "background": ["type": "boolean", "description": "true = в фоне"],
                ],
                "required": ["task"],
            ],
        ],
        [
            "name": "agent_list",
            "description": "Показать недавние/активные сессии агентов (runId, агент, статус, фон/нет, последняя задача) — чтобы решить, какую продолжить или остановить.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
        ],
        [
            "name": "agent_status",
            "description": "Статус и текущий вывод фонового запуска по runId (работает/готово/упал + хвост вывода).",
            "inputSchema": [
                "type": "object",
                "properties": ["runId": ["type": "string"]],
                "required": ["runId"],
            ],
        ],
        [
            "name": "agent_stop",
            "description": "Остановить фоновый запуск агента по runId (убивает процесс).",
            "inputSchema": [
                "type": "object",
                "properties": ["runId": ["type": "string"]],
                "required": ["runId"],
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
    private static func toolResult(id: Any?, text: String, isError: Bool = false) {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if isError { result["isError"] = true }
        respond(id: id, result: result)
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
    private static func log(_ s: String) {
        FileHandle.standardError.write(Data(("[cam-agents] " + s + "\n").utf8))
    }
}
