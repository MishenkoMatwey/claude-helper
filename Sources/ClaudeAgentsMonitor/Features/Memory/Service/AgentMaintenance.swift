import Foundation

/// Re-generates existing agents onto the v3 memory stack: rewrites their `.md`
/// (fresh v3 memory + variables blocks, MCP tool grant), registers the memory
/// MCP server in `.mcp.json`, and mirrors plain variables into memory.
///
/// Idempotent — `Agent.promptWithoutInjectedBlocks` strips the injected blocks
/// (`## Память`, `## Variables & Secrets`, `## Available skills`) before re-save.
enum AgentMaintenance {
    /// Tool grants from the v2 era that no longer apply; dropped on rewire.
    private static func cleanTools(_ tools: [String], agent: String) -> [String] {
        tools.filter { t in
            if t.hasPrefix("Edit(") && t.contains("/memory/") { return false }
            if t == "Bash(tail:*)" || t == "Bash(grep:*)" { return false }
            if t.hasPrefix("mcp__cam-memory-") { return false } // re-added by save()
            return true
        }
    }

    @discardableResult
    static func rewireAllToV3(paths: AgentPaths) -> Int {
        let skills = SkillLoader.loadAll()
        var done = 0
        for agent in AgentLoader.loadAll() {
            let attached = Set(agent.attachedSkills)
            let agentSkills = skills.filter { attached.contains($0.name) }
            do {
                _ = try AgentWriter.save(
                    name: agent.name,
                    description: agent.description,
                    model: agent.model ?? "default",
                    tools: cleanTools(agent.tools, agent: agent.name),
                    systemPrompt: agent.promptWithoutInjectedBlocks,
                    skills: agentSkills,
                    overwrite: true,
                    iconAsset: agent.iconAsset,
                    iconSymbol: agent.iconSymbol,
                    iconColor: agent.iconColor,
                    role: agent.role
                )
                AgentVariablesService.syncToMemory(for: agent.name)
                done += 1
            } catch {
                FileHandle.standardError.write(Data(
                    "[cam-memory] rewire failed for \(agent.name): \(error)\n".utf8))
            }
        }
        return done
    }

    /// CLI entry (`--rewire-all [--project <path>]`). Defaults to the global namespace.
    static func rewireAllCLI() {
        AgentPaths.current = AgentCLIScope.resolve()
        let n = rewireAllToV3(paths: .current)
        print("✅ rewire-all [\(AgentPaths.current.projectName)]: \(n) agents rewired to v3")
    }

    /// CLI entry (`--rewire-orchestrators [--project <path>]`): rebuild the
    /// orchestrator(s) so they get resumable-session tools (cam-agents) + prompt.
    static func rewireOrchestratorsCLI() {
        AgentPaths.current = AgentCLIScope.resolve()
        let agents = AgentLoader.loadAll()
        // Detect orchestrators by role/name OR by the "orchestrator" name prefix —
        // covers renamed ones (orchestrator-clussters) that lost their role line.
        let targets = agents.filter {
            $0.isOrchestrator || $0.name.lowercased().hasPrefix("orchestrator")
        }
        guard !targets.isEmpty else {
            print("ℹ️ [\(AgentPaths.current.projectName)] оркестратор не найден — пропуск")
            return
        }
        let workflows = WorkflowLoader.loadAll()
        for t in targets {
            do {
                _ = try OrchestratorBuilder.build(agents: agents, workflows: workflows, targetName: t.name)
                print("✅ [\(AgentPaths.current.projectName)] \(t.name): обновлён (resumable sessions + role)")
            } catch {
                print("❌ \(t.name) failed: \(error)")
            }
        }
    }
}

/// Resolves the agent namespace for CLI batch ops from a `--project <path>` flag.
enum AgentCLIScope {
    static func resolve() -> AgentPaths {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--project"), i + 1 < args.count {
            let path = (args[i + 1] as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: path)
            return .project(name: url.lastPathComponent, root: url)
        }
        return .global
    }
}
