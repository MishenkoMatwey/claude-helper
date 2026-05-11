import Foundation

enum AgentWriterError: LocalizedError {
    case invalidName
    case alreadyExists(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Имя должно содержать только буквы, цифры и дефис (a-z, 0-9, -)."
        case .alreadyExists(let name): return "Агент '\(name)' уже существует."
        case .writeFailed(let msg): return "Не удалось записать файл: \(msg)"
        }
    }
}

enum AgentWriter {
    static func validate(name: String) -> Bool {
        let pattern = "^[a-z0-9][a-z0-9-]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    static func save(
        name: String,
        description: String,
        model: String,
        tools: [String],
        systemPrompt: String,
        skills: [Skill] = [],
        overwrite: Bool = false
    ) throws -> URL {
        guard validate(name: name) else { throw AgentWriterError.invalidName }

        let dir = AgentLoader.agentsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("memory"),
            withIntermediateDirectories: true
        )

        let url = dir.appendingPathComponent("\(name).md")
        if !overwrite && FileManager.default.fileExists(atPath: url.path) {
            throw AgentWriterError.alreadyExists(name)
        }

        var allTools = tools
        if !skills.isEmpty && !allTools.contains("Skill") {
            allTools.append("Skill")
        }
        // Always grant memory access — Read for shared, Edit for own private file + playbooks.
        let memoryReadTools = ["Read"]
        for t in memoryReadTools where !allTools.contains(t) {
            allTools.append(t)
        }
        if !allTools.contains("Edit") {
            let editPrivateMemory = "Edit(~/.claude/agents/memory/\(name).md)"
            let editPlaybooks = "Edit(~/.claude/agents/memory/\(name).playbooks.md)"
            if !allTools.contains(editPrivateMemory) { allTools.append(editPrivateMemory) }
            if !allTools.contains(editPlaybooks) { allTools.append(editPlaybooks) }
        }
        // Allow Bash(security:*) for keychain access of own secrets.
        let securityTool = "Bash(security:*)"
        if !allTools.contains("Bash") && !allTools.contains(securityTool) {
            allTools.append(securityTool)
        }

        let toolsLine = allTools.isEmpty ? "" : "tools: \(allTools.joined(separator: ", "))\n"
        let modelLine = (model.isEmpty || model == "default") ? "" : "model: \(model)\n"
        let frontmatter = """
        ---
        name: \(name)
        description: \(description.replacingOccurrences(of: "\n", with: " "))
        \(modelLine)\(toolsLine)---

        """

        var fullPrompt = systemPrompt
        fullPrompt += memoryProtocolBlock(agentName: name)
        fullPrompt += variablesBlock(agentName: name)
        if !skills.isEmpty {
            let skillsBlock = "\n\n## Available skills\nInvoke via the Skill tool with `skill: \"<name>\"`:\n" +
                skills.map { "- **\($0.name)** — \($0.description)" }.joined(separator: "\n")
            fullPrompt += skillsBlock
        }

        let content = frontmatter + fullPrompt + "\n"

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AgentWriterError.writeFailed(error.localizedDescription)
        }

        // Touch private memory + playbooks files.
        let memoryURL = dir.appendingPathComponent("memory/\(name).md")
        if !FileManager.default.fileExists(atPath: memoryURL.path) {
            let stub = "# \(name) — private memory\n\n_Журнал: что узнал, какие решения принял._\n\n"
            try? stub.write(to: memoryURL, atomically: true, encoding: .utf8)
        }
        let playbooksURL = dir.appendingPathComponent("memory/\(name).playbooks.md")
        if !FileManager.default.fileExists(atPath: playbooksURL.path) {
            let stub = """
            # \(name) — playbooks

            Структурированные процедуры. Формат каждой записи:

            ```
            ## <короткое-имя>
            **Trigger**: фразы юзера которые активируют этот playbook
            **Last verified**: YYYY-MM-DD
            **Tokens cost**: ~N (was M first time)

            ### Steps
            1. Точная команда / API call
            2. Следующий шаг

            ### Notes
            - подводные камни, edge cases

            ### Example output
            <фрагмент>
            ```

            """
            try? stub.write(to: playbooksURL, atomically: true, encoding: .utf8)
        }

        return url
    }

    static func delete(_ agent: Agent) throws {
        try FileManager.default.removeItem(at: agent.filePath)
    }

    static func variablesBlock(agentName: String) -> String {
        """


        ## Variables & Secrets

        У тебя могут быть переменные настроенные через UI:

        - **Plain переменные** — лежат в `\(AgentPaths.current.memoryDir.path)/\(agentName).vars.json`. Прочитай файл (Read), достань нужное значение по ключу.
        - **Секреты** — в macOS Keychain, service `\(AgentVariablesService.keychainService(for: agentName))`. Получай так:
          ```
          security find-generic-password -s "\(AgentVariablesService.keychainService(for: agentName))" -a "<KEY>" -w
          ```
          (вернёт значение в stdout одной строкой)

        ### Правила
        - **НИКОГДА** не пиши значения секретов в свою память (`memory/...md`), playbooks или ответы юзеру в открытом виде. Используй маску `***`.
        - В playbook сохраняй только **имя переменной** (`$DB_PASSWORD`), не значение.
        - Если секрета нет — попроси юзера добавить через UI агента, не запрашивай в чате.
        - Plain переменные можешь логировать (URL, host, user — обычно не секретны).
        """
    }

    static func memoryProtocolBlock(agentName: String) -> String {
        """


        ## Memory protocol

        У тебя есть постоянная память между сессиями. **Используй её всегда.**

        ### В начале КАЖДОЙ задачи:
        1. Прочитай `~/.claude/agents/SHARED.md` — общая память всех агентов
        2. Прочитай `~/.claude/agents/memory/\(agentName).md` — твой журнал
        3. Прочитай `~/.claude/agents/memory/\(agentName).playbooks.md` — твои готовые процедуры
        4. **Если задача матчит trigger из playbook → выполняй по шагам, не исследуй заново.** Цель playbook — экономия токенов.

        ### В конце задачи — обнови ЖУРНАЛ:
        5. Допиши в `\(agentName).md` важные выводы:
           - Что узнал нового про проект/код
           - Какие решения принял и почему
           - Какие подводные камни нашёл
           Формат:
           ```
           ## YYYY-MM-DD HH:MM — <короткое название>
           <2-4 строки сути>
           ```

        ### В конце задачи — реши: создавать/обновлять PLAYBOOK?
        6. **Сохрани playbook ЕСЛИ хотя бы одно:**
           - ✓ Освоил процедуру из 3+ шагов с внешним API/инструментом (Jira, GitHub, БД, etc.)
           - ✓ Пришлось 2+ раз пробовать чтобы понять как работает
           - ✓ Юзер сказал "научись делать X" / "разберись как X" / "запомни как X"
           - ✓ Обнаружил эндпоинт/команду/паттерн которого не было в playbooks
           - ✓ Ты в TRAINING MODE (см. system prompt)

        7. **НЕ сохраняй** если: простой вопрос-ответ; чисто кодовое изменение в текущем файле; уже есть похожий playbook (тогда **обнови** его — увеличь Last verified, уточни шаги).

        8. Формат playbook (дописывай в `\(agentName).playbooks.md`):
           ```
           ## <короткое-имя-snake-case>
           **Trigger**: "фраза1", "фраза2", "паттерн запроса"
           **Last verified**: YYYY-MM-DD
           **Tokens cost**: ~N (was M first time)

           ### Steps
           1. Точная команда: `cmd --flag value`
           2. Следующий шаг

           ### Notes
           - подводные камни

           ### Example output
           <реальный фрагмент>
           ```

        ### Shared memory
        Если узнал что-то полезное **всем** агентам — допиши в `SHARED.md` (попроси Edit-permission если нет).

        ### Не дублируй
        Перед записью проверь — может уже есть похожая запись. Обновляй, не плоди копии.
        """
    }
}
