package com.clussters.claude

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.ui.Messages
import com.intellij.util.Alarm
import org.jetbrains.plugins.terminal.TerminalToolWindowManager

class StartOrchestratorAction : AnAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return

        val basePath = project.basePath ?: System.getProperty("user.home")
        val agentsRoot = findAgentsRoot(basePath) ?: basePath

        // Discover real orchestrator agents from .claude/agents/ (prefers role: orchestrator
        // and name "orchestrator"), so we run --agent <real-name> instead of the hard-coded
        // "orchestrator", which would resolve to ~/.claude/agents/orchestrator.md.
        val candidates = discoverOrchestrators(agentsRoot).ifEmpty { listOf("orchestrator") }

        val agent: String = if (candidates.size == 1) {
            candidates.first()
        } else {
            val idx = Messages.showChooseDialog(
                project,
                "Multiple orchestrator agents found in $agentsRoot.\nWhich one to launch?",
                "Claude Launcher",
                null,
                candidates.toTypedArray(),
                candidates.first()
            )
            if (idx < 0) return
            candidates[idx]
        }

        // Pass original IDE project path via --add-dir so the agent can still access it.
        // cwd is `agentsRoot` because Claude Code only scans `.claude/agents/` in cwd,
        // not in --add-dir paths.
        // --append-system-prompt tells the orchestrator the user's active IDE scope, so
        // delegated code-agents (developer-BE, reviewer-BE, git, etc.) focus on this subpath
        // instead of scanning the whole multi-service root.
        val scopeNote = "ACTIVE IDE SCOPE: ${basePath}. " +
            "User's IDE is opened on this subpath of ${agentsRoot}. " +
            "When delegating to developer-BE, reviewer-BE, git or any code-touching agent, " +
            "instruct them to work ONLY inside this scope unless the user explicitly says otherwise. " +
            "Don't grep/Read/Glob across the whole monorepo by default."
        val scopeEscaped = scopeNote.replace("'", "'\\''")
        val command = "claude --agent $agent --add-dir \"$basePath\" --append-system-prompt '$scopeEscaped'"

        val terminalManager = TerminalToolWindowManager.getInstance(project)
        val widget = terminalManager.createShellWidget(
            agentsRoot,
            "Claude: $agent",
            true,
            true
        )

        // Shell needs ~700ms to initialise (~/.zshrc, PATH, prompt) — without delay
        // the command lands before the prompt and gets lost.
        val alarm = Alarm(Alarm.ThreadToUse.SWING_THREAD, project)
        alarm.addRequest({
            ApplicationManager.getApplication().invokeLater {
                sendCommand(widget, command)
            }
        }, 800)
    }

    /** Tries multiple known APIs to push a command into a terminal widget. */
    private fun sendCommand(widget: Any, command: String) {
        if (invoke(widget, "executeCommand", command)) return
        if (invoke(widget, "sendCommandToExecute", command)) return
        invokeSendText(widget, "$command\n")
    }

    private fun invoke(target: Any, methodName: String, arg: String): Boolean {
        return try {
            val m = findMethod(target.javaClass, methodName, String::class.java) ?: return false
            m.invoke(target, arg)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun invokeSendText(widget: Any, text: String) {
        // Walk up the class hierarchy looking for a `sendText` / `sendString` method.
        for (name in arrayOf("sendText", "sendString")) {
            try {
                val m = findMethod(widget.javaClass, name, String::class.java) ?: continue
                m.invoke(widget, text)
                return
            } catch (_: Throwable) { /* keep trying */ }
        }
        // Final fallback — try terminalStarter.sendString(text, true)
        try {
            val starterGetter = findMethod(widget.javaClass, "getTerminalStarter") ?: return
            val starter = starterGetter.invoke(widget) ?: return
            val sendString = starter.javaClass.methods.firstOrNull {
                it.name == "sendString" && it.parameterCount == 2
            } ?: return
            sendString.invoke(starter, text, true)
        } catch (_: Throwable) { /* give up silently */ }
    }

    private fun findMethod(clazz: Class<*>, name: String, vararg params: Class<*>): java.lang.reflect.Method? {
        var c: Class<*>? = clazz
        while (c != null) {
            val m = c.declaredMethods.firstOrNull { mm ->
                mm.name == name && mm.parameterTypes.size == params.size &&
                    mm.parameterTypes.zip(params).all { pair -> pair.first == pair.second }
            }
            if (m != null) { m.isAccessible = true; return m }
            c = c.superclass
        }
        return null
    }

    // Scans agentsRoot/.claude/agents/ for agents that look like an orchestrator —
    // either declare `role: orchestrator` in frontmatter or have `name: orchestrator`.
    // Returns their names without the .md suffix. Renamed project orchestrators come
    // before the default "orchestrator" so callers can pick the first().
    private fun discoverOrchestrators(agentsRoot: String): List<String> {
        val dir = java.io.File(agentsRoot, ".claude/agents")
        if (!dir.isDirectory) return emptyList()
        val mdFiles = dir.listFiles { f -> f.isFile && f.name.endsWith(".md") } ?: return emptyList()
        val matches = mutableListOf<String>()
        for (f in mdFiles) {
            val (name, role) = readFrontmatterNameAndRole(f) ?: continue
            val resolvedName = name ?: f.nameWithoutExtension
            val isOrch = role?.lowercase() == "orchestrator" || resolvedName == "orchestrator"
            if (isOrch) matches.add(resolvedName)
        }
        // Stable ordering: non-default names first (so renamed project orchestrators win
        // when caller picks `.first()`), then "orchestrator" itself.
        return matches.sortedWith(compareBy<String>({ if (it == "orchestrator") 1 else 0 }, { it }))
    }

    /** Parses just the YAML frontmatter (between two `---` lines) and returns name + role. */
    private fun readFrontmatterNameAndRole(file: java.io.File): Pair<String?, String?>? {
        val lines = try { file.readLines() } catch (_: Throwable) { return null }
        if (lines.firstOrNull()?.trim() != "---") return null
        var name: String? = null
        var role: String? = null
        for (line in lines.drop(1)) {
            if (line.trim() == "---") break
            val idx = line.indexOf(':')
            if (idx <= 0) continue
            val key = line.substring(0, idx).trim().lowercase()
            val value = line.substring(idx + 1).trim().trim('"').trim()
            when (key) {
                "name" -> name = value
                "role" -> role = value
            }
        }
        return name to role
    }

    private fun findAgentsRoot(startPath: String): String? {
        var dir = java.io.File(startPath)
        val home = java.io.File(System.getProperty("user.home"))
        while (dir.parentFile != null && dir != home) {
            if (java.io.File(dir, ".claude/agents").isDirectory) return dir.absolutePath
            dir = dir.parentFile
        }
        return null
    }
}
