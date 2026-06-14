import Foundation

/// Lightweight self-test harness, run via `ClaudeAgentsMonitor --selftest`.
///
/// This environment ships Command Line Tools only (no Xcode), so `swift test`
/// can't link XCTest/swift-testing. Until full Xcode is available, this harness
/// is the runnable test suite — it exercises the pure services (memory store,
/// migration, agent-run store/runner, wiring) without a GUI or network.
enum SelfTest {
    static func runAll() {
        let suite = Suite()
        memoryStore(suite)
        memoryWiring(suite)
        memoryMigration(suite)
        agentRuns(suite)
        suite.finish()
    }

    // MARK: - Suites

    private static func memoryStore(_ s: Suite) {
        s.group("MemoryStore") {
            let store = try MemoryStore(inMemory: true)
            let rule = MemoryNote(agent: "rev", kind: .rule, title: "Commits", body: "[CLS-XXX]", tags: ["style"])
            let fact = MemoryNote(agent: "rev", kind: .fact, title: "Token dup", body: "auth токен в 3 местах", tags: ["auth"])
            let session = MemoryNote(agent: "rev", kind: .session, title: "ревью auth", body: "null-баг", tags: ["auth"])
            try store.save(rule); try store.save(fact); try store.save(session)
            s.expect(try store.allNotes(agent: "rev").count == 3, "allNotes == 3")

            try store.link(MemoryEdge(src: fact.id, dst: session.id, rel: .relates))
            s.expect(try store.neighbors(of: fact.id).contains { $0.id == session.id }, "neighbor link")
            s.expect(try store.allEdges().count == 1, "edges == 1")

            let hits = try store.search("auth токен", agent: "rev", limit: 5)
            s.expect(hits.contains { $0.id == fact.id }, "search finds fact")
            if let f = try store.note(id: fact.id) {
                s.expect(f.useCount >= 1, "useCount bumped by search")
            }

            // shared note visible cross-agent
            try store.save(MemoryNote(agent: "", kind: .fact, title: "Shared", body: "всем", tags: []))
            s.expect(try store.allNotes(agent: "other").contains { $0.title == "Shared" }, "shared visible cross-agent")

            try store.archive(id: rule.id)
            s.expect(try !store.allNotes(agent: "rev").contains { $0.id == rule.id }, "archived hidden")

            try store.delete(id: fact.id)
            s.expect(try store.allEdges().isEmpty, "edge cascaded on delete")

            // variable mirror upsert-in-place
            try store.upsertVariable(agent: "rev", key: "BOARD", value: "2")
            try store.upsertVariable(agent: "rev", key: "BOARD", value: "3")
            let vars = try store.allNotes(agent: "rev").filter { $0.kind == .variable }
            s.expect(vars.count == 1 && vars.first?.body == "3", "variable upsert in-place + updated")
            try store.deleteVariable(agent: "rev", key: "BOARD")
            s.expect(try store.allNotes(agent: "rev").filter { $0.kind == .variable }.isEmpty, "variable deleted")
        }

        s.group("FTS query builder") {
            s.expect(MemoryStore.ftsQuery(from: "auth токен!!") == "\"auth\"* OR \"токен\"*", "ftsQuery tokens + prefix-OR")
            s.expect(MemoryStore.ftsQuery(from: "  ") == "", "ftsQuery empty input")
        }
    }

    private static func memoryWiring(_ s: Suite) {
        s.group("Agent v3 wiring") {
            try withTempProject("WireTest") {
                let agent = "rev"
                let url = try AgentWriter.save(name: agent, description: "d", model: "default",
                                               tools: ["Read"], systemPrompt: "Ты ревьюер.")
                let md = try String(contentsOf: url, encoding: .utf8)
                let server = MemoryMCPConfig.serverName(for: agent)
                s.expect(md.contains("mcp__\(server)"), "frontmatter grants memory MCP tool")
                s.expect(md.contains("## Память"), "v3 memory protocol present")
                s.expect(!md.contains("tail -c 5000"), "old v2 protocol removed")

                let mcp = try JSONSerialization.jsonObject(
                    with: Data(contentsOf: AgentPaths.current.projectRoot.appendingPathComponent(".mcp.json")))
                let servers = (mcp as? [String: Any])?["mcpServers"] as? [String: Any]
                s.expect(servers?[server] != nil, ".mcp.json registers memory server")

                if let a = AgentLoader.loadAll().first(where: { $0.name == agent }) {
                    try AgentWriter.delete(a)
                    let mcp2 = try JSONSerialization.jsonObject(
                        with: Data(contentsOf: AgentPaths.current.projectRoot.appendingPathComponent(".mcp.json")))
                    let servers2 = (mcp2 as? [String: Any])?["mcpServers"] as? [String: Any]
                    s.expect(servers2?[server] == nil, "unregistered on delete")
                } else { s.expect(false, "agent loadable for delete") }
            }
        }
    }

    private static func memoryMigration(_ s: Suite) {
        s.group("Memory v2→v3 migration") {
            s.expect(MemoryMigration.sections(in: "# h1\n\n## A\nbody a\n\n## B\nbody b").count == 2,
                     "section splitter")
            let parsed = MemoryMigration.parseSessionHeading("2026-06-14 ревью [#auth #bug]")
            s.expect(parsed.tags == ["auth", "bug"], "session heading tags parsed")
            s.expect(parsed.title == "2026-06-14 ревью", "session heading title")

            try withTempProject("MigTest") {
                let agent = "rev"
                let dir = AgentPaths.current.memoryDir.appendingPathComponent(agent)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try "## Project\n17 services".write(to: dir.appendingPathComponent("context.md"), atomically: true, encoding: .utf8)
                try "## flow\n1. a\n2. b".write(to: dir.appendingPathComponent("playbooks.md"), atomically: true, encoding: .utf8)
                try "## 2026-06-13 ревью [#auth]\nnull-баг".write(to: dir.appendingPathComponent("log.md"), atomically: true, encoding: .utf8)
                let store = try MemoryStore(path: AgentPaths.current.memoryDBFile)
                let n = try MemoryMigration.migrate(agent: agent, store: store, paths: .current)
                s.expect(n >= 3, "migrate created >= 3 notes (\(n))")
                let notes = try store.allNotes(agent: agent)
                s.expect(notes.contains { $0.kind == .fact && $0.title == "Project" }, "context → fact")
                s.expect(notes.contains { $0.kind == .session && $0.tags.contains("auth") }, "log → session w/ tags")
                s.expect(try MemoryMigration.migrate(agent: agent, store: store, paths: .current) == 0, "migration idempotent")
            }
        }
    }

    private static func agentRuns(_ s: Suite) {
        s.group("AgentRunStore") {
            try withTempDir { dir in
                let store = AgentRunStore(path: dir.appendingPathComponent("agent-runs.json"))
                let id = AgentRunStore.newRunID()
                store.upsert(AgentRun(id: id, agent: "be", sessionId: "sess-1",
                                      lastTask: "build", status: "done", updatedAtMillis: 0))
                s.expect(store.get(id)?.sessionId == "sess-1", "upsert + get")
                s.expect(store.latest(forAgent: "be")?.id == id, "latest by agent")

                // background run with a dead pid → reconcile marks done from log
                let bgId = AgentRunStore.newRunID()
                try #"{"session_id":"sess-2","result":"ok","is_error":false}"#
                    .write(to: store.logURL(bgId), atomically: true, encoding: .utf8)
                store.upsert(AgentRun(id: bgId, agent: "be", sessionId: nil, lastTask: "bg",
                                      status: "running", updatedAtMillis: 0, pid: 999_999, background: true))
                _ = store.reconcileRunning()
                let r = store.get(bgId)
                s.expect(r?.status == "done" && r?.sessionId == "sess-2", "reconcile dead bg run → done + session")

                store.stop(id)  // no pid → no-op on get(id) (status already done); just must not crash
                store.remove(id)
                s.expect(store.get(id) == nil, "remove")
            }
        }

        s.group("AgentRunner") {
            try withTempDir { dir in
                let log = dir.appendingPathComponent("x.out")
                try #"{"session_id":"abc","result":"hello","is_error":false}"#
                    .write(to: log, atomically: true, encoding: .utf8)
                let res = AgentRunner.parseLog(log)
                s.expect(res?.sessionId == "abc" && res?.text == "hello", "parseLog extracts session + result")
            }
            s.expect(!AgentRunner.isAlive(pid: 0), "isAlive(0) == false")
            s.expect(AgentRunner.isAlive(pid: Int32(ProcessInfo.processInfo.processIdentifier)), "isAlive(self) == true")
        }

        s.group("MCP config names") {
            s.expect(MemoryMCPConfig.serverName(for: "be") == "cam-memory-be", "memory server name")
            s.expect(MemoryMCPConfig.agentsServerName == "cam-agents", "agents server name")
        }
    }

    // MARK: - Temp helpers

    private static func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cam-selftest-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private static func withTempProject(_ name: String, _ body: () throws -> Void) throws {
        let saved = AgentPaths.current
        defer { AgentPaths.current = saved }
        try withTempDir { dir in
            AgentPaths.current = .project(name: name, root: dir)
            try body()
        }
    }
}

/// Minimal pass/fail collector with grouped output and a non-zero exit on failure.
private final class Suite {
    private var passed = 0
    private var failed = 0

    func group(_ name: String, _ body: () throws -> Void) {
        print("▸ \(name)")
        do { try body() }
        catch { print("  ✗ ERROR: \(error)"); failed += 1 }
    }

    func expect(_ cond: @autoclosure () throws -> Bool, _ name: String) {
        do {
            if try cond() { print("  ✓ \(name)"); passed += 1 }
            else { print("  ✗ FAIL: \(name)"); failed += 1 }
        } catch { print("  ✗ ERROR in \(name): \(error)"); failed += 1 }
    }

    func finish() {
        print("\n\(failed == 0 ? "✅" : "❌") \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
