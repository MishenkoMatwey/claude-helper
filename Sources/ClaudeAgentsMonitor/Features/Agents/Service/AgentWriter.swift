import Foundation

enum AgentWriterError: LocalizedError {
    case invalidName
    case alreadyExists(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Name must contain only letters, digits and hyphens (a-z, A-Z, 0-9, -)."
        case .alreadyExists(let name): return "Agent '\(name)' already exists."
        case .writeFailed(let msg): return "Failed to write file: \(msg)"
        }
    }
}

enum AgentWriter {
    static func validate(name: String) -> Bool {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9-]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    static func save(
        name: String,
        description: String,
        model: String,
        tools: [String],
        systemPrompt: String,
        skills: [Skill] = [],
        overwrite: Bool = false,
        iconAsset: String? = nil,
        iconSymbol: String? = nil,
        iconColor: String? = nil,
        role: String? = nil
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
        // Grant the v3 memory MCP server (search/write/link tools live there).
        let memoryServerTool = "mcp__\(MemoryMCPConfig.serverName(for: name))"
        if !allTools.contains(memoryServerTool) {
            allTools.append(memoryServerTool)
        }
        // Allow Bash(security:*) for keychain access of own secrets.
        if !allTools.contains("Bash") && !allTools.contains("Bash(security:*)") {
            allTools.append("Bash(security:*)")
        }

        let toolsLine = allTools.isEmpty ? "" : "tools: \(allTools.joined(separator: ", "))\n"
        let modelLine = (model.isEmpty || model == "default") ? "" : "model: \(model)\n"
        let roleLine = (role?.isEmpty == false) ? "role: \(role!)\n" : ""
        var iconLines = ""
        if let v = iconAsset, !v.isEmpty  { iconLines += "icon-asset: \(v)\n" }
        if let v = iconSymbol, !v.isEmpty { iconLines += "icon-symbol: \(v)\n" }
        if let v = iconColor, !v.isEmpty  { iconLines += "icon-color: \(v)\n" }
        let frontmatter = """
        ---
        name: \(name)
        description: \(description.replacingOccurrences(of: "\n", with: " "))
        \(modelLine)\(roleLine)\(toolsLine)\(iconLines)---

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

        // Register the per-agent memory MCP server in the project's .mcp.json so
        // `claude` launches it and exposes memory_search / _write / _link.
        MemoryMCPConfig.register(agentName: name, paths: .current)

        return url
    }

    static func delete(_ agent: Agent) throws {
        MemoryMCPConfig.unregister(agentName: agent.name, paths: .current)
        try FileManager.default.removeItem(at: agent.filePath)
    }

    static func variablesBlock(agentName: String) -> String {
        let service = AgentVariablesService.keychainService(for: agentName)
        let memPrefix = "mcp__\(MemoryMCPConfig.serverName(for: agentName))__"
        return """


        ## Variables & Secrets

        У тебя есть настроенные переменные двух видов:

        - **Обычные переменные** (URL, host, board ID, имя пользователя) — лежат в твоей **памяти** как заметки `kind=var`. Найди нужную через `\(memPrefix)memory_search` (по имени ключа или теме). Если значение уже есть — **используй его, не спрашивай у пользователя**.
        - **Секреты** (пароли, токены) — в macOS Keychain, в память НЕ пишутся. Достань так:
          ```
          security find-generic-password -s "\(service)" -a "<KEY>" -w
          ```
          (вернёт значение в stdout одной строкой)

        ### Правила
        - **НИКОГДА** не пиши значения секретов в память или ответы юзеру в открытом виде — маскируй `***`.
        - Если секрета нет в Keychain — попроси добавить через UI агента, не запрашивай в чате.
        - Прежде чем спросить значение — сделай `memory_search` по ключу: оно почти наверняка уже есть.
        """
    }

    static func memoryProtocolBlock(agentName: String) -> String {
        let server = MemoryMCPConfig.serverName(for: agentName)
        let prefix = "mcp__\(server)__"
        return """


        ## Память (между сессиями)

        У тебя есть постоянная память через MCP-инструменты сервера `\(server)`:
        - `\(prefix)memory_search` — найти релевантные заметки;
        - `\(prefix)memory_write` — сохранить/обновить заметку;
        - `\(prefix)memory_link` — связать две заметки.

        Память умная: поиск возвращает **только релевантный топ**, не всю базу. Не читай файлы памяти — работай через инструменты.

        ### В начале КАЖДОЙ задачи
        1. Вызови `\(prefix)memory_search` с запросом по сути задачи.
           Получишь топ заметок: факты о проекте, правила, итоги прошлых сессий.
        2. Если среди них есть ответ/процедура — **не исследуй заново**, используй.

        ### В конце задачи
        3. Новый факт о проекте/коде → `\(prefix)memory_write` (kind="fact").
        4. Новое правило/конвенция → `memory_write` (kind="rule").
        5. Освоенная процедура из 3+ шагов → `memory_write` (kind="playbook").
        6. Итог сессии (что сделал, что нашёл) → `memory_write` (kind="session"), 2-4 строки.
        7. Связал находку с прошлой заметкой → `memory_link`.

        ### Правила
        - Заметка с тем же title **обновляется**, а не дублируется — пиши смело.
        - Ставь `tags` (например `["auth","refactor"]`) — по ним идёт поиск.
        - **Секреты/пароли в память НЕ пиши** (см. раздел Variables & Secrets) — только имена переменных.
        - Память про прошлые сессии = ищи `kind:session` через `memory_search` по теме.
        """
    }
}
