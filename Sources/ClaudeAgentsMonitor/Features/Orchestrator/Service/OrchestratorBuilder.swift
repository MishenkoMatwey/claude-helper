import Foundation

enum OrchestratorBuilder {
    static let agentName = "orchestrator"

    /// Builds the orchestrator agent file from current state of agents + workflows.
    /// Overwrites the existing orchestrator.md if it exists.
    static func build(agents: [Agent], workflows: [Workflow]) throws -> URL {
        let others = agents.filter { $0.name != agentName }
        let prompt = buildPrompt(agents: others, workflows: workflows)
        return try AgentWriter.save(
            name: agentName,
            description: "Маршрутизатор: принимает любую задачу, выбирает агента или запускает workflow.",
            model: "sonnet",
            tools: ["Read", "Glob", "Grep", "Task", "TodoWrite"],
            systemPrompt: prompt,
            skills: [],
            overwrite: true
        )
    }

    private static func buildPrompt(agents: [Agent], workflows: [Workflow]) -> String {
        var s = """
        Ты — **orchestrator**. Твоя задача: получив сообщение пользователя, выбрать правильного агента (или цепочку) и делегировать через Task tool. **Не выполняй задачу сам** — ты диспетчер.

        ## Алгоритм роутинга

        1. Сначала проверь **WORKFLOWS** ниже — если сообщение пользователя матчит trigger любого workflow, запусти этот workflow по шагам.
        2. Если ни один workflow не подходит — выбери **один agent** из AGENTS чьё `description` лучше всего подходит, и делегируй ему через Task.
        3. Если непонятно кому делегировать — задай юзеру **один короткий уточняющий вопрос** (но не подряд несколько).
        4. После завершения каждого шага — кратко суммаризируй результат и переходи к следующему шагу или возврату юзеру.

        ## Запуск агента

        Для делегирования используй Task tool:
        ```
        Task(subagent_type: "<agent-name>", description: "<короткое описание>", prompt: "<полная задача с контекстом>")
        ```

        Агент сам прочитает свою память + playbooks и выполнит задачу. Результат вернётся тебе — суммаризируй для юзера или передай дальше по workflow.

        """

        s += "\n## AGENTS\n\n"
        if agents.isEmpty {
            s += "_Ни одного агента не создано. Скажи юзеру создать агентов через UI._\n"
        } else {
            for a in agents {
                s += "### \(a.name)\n"
                s += "**Description**: \(a.description.isEmpty ? "(no description)" : a.description)\n"
                if !a.tools.isEmpty {
                    s += "**Tools**: \(a.tools.prefix(8).joined(separator: ", "))\n"
                }
                if !a.attachedSkills.isEmpty {
                    s += "**Skills**: \(a.attachedSkills.joined(separator: ", "))\n"
                }
                s += "\n"
            }
        }

        s += "## WORKFLOWS\n\n"
        if workflows.isEmpty {
            s += "_Workflow'ов нет. Если юзер описывает многошаговый процесс — предложи создать workflow в UI._\n"
        } else {
            for wf in workflows {
                s += "### \(wf.name)\n"
                s += "**Description**: \(wf.description)\n"
                if !wf.triggers.isEmpty {
                    s += "**Triggers**: " + wf.triggers.map { "`\($0)`" }.joined(separator: ", ") + "\n"
                }
                s += "\n**Steps:**\n\(wf.steps)\n\n---\n\n"
            }
        }

        s += """

        ## Правила

        - **НЕ выполняй сам** ничего что должен сделать специализированный агент. Ты только маршрутизатор.
        - При запуске workflow — следуй шагам строго по порядку. Если шаг провален и описано "on_fail" — поступай по нему. Иначе — останови, расскажи юзеру что произошло.
        - **Пробрасывай контекст** между шагами: вывод предыдущего агента передавай в prompt следующего.
        - Если матч с trigger неточный (юзер сказал близко, но не идентично) — всё равно матчь, не будь буквоедом.
        - Если у юзера явный shortcut ("просто git pull", "только review без коммита") — НЕ запускай полный workflow, делегируй одному агенту.
        """

        return s
    }
}
