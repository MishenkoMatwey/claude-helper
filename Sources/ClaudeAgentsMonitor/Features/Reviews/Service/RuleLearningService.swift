import Foundation

/// Background job: read author replies to our review comments and update
/// `reviewer-BE/rules.yaml` accordingly (refine existing rules, add false-positives,
/// add new rules from explicit policy comments).
///
/// Spawns claude in the background, much like ReviewRunner but with a single-shot
/// prompt addressed to reviewer-BE.
@MainActor
final class RuleLearningService: ObservableObject {
    let projectPath: URL

    @Published var isLearning: Bool = false
    @Published var lastResult: String?

    init(projectPath: URL) {
        self.projectPath = projectPath
    }

    var learningQueueFile: URL {
        projectPath.appendingPathComponent(".claude/reviews/learning-queue.json")
    }

    var pendingDialogsCount: Int {
        guard let data = try? Data(contentsOf: learningQueueFile) else { return 0 }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([GitlabRefreshService.LearningDialog].self, from: data))?.count ?? 0
    }

    /// Start a claude subprocess that reads the queue and updates rules.yaml.
    @discardableResult
    func start() -> Bool {
        guard !isLearning else { return false }
        guard pendingDialogsCount > 0 else {
            lastResult = "Нечему учиться — нет ответов автора."
            return false
        }
        let claudePath: String? = {
            for p in [
                "\(NSHomeDirectory())/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
            ] where FileManager.default.isExecutableFile(atPath: p) { return p }
            return nil
        }()
        guard let claudePath else {
            lastResult = "claude CLI не найден"
            return false
        }

        // log + result dirs
        let logDir = projectPath.appendingPathComponent(".claude/reviews/_learning")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let ts: String = {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        }()
        let logURL = logDir.appendingPathComponent("\(ts)-log.txt")
        let debugURL = logDir.appendingPathComponent("\(ts)-debug.txt")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else { return false }
        logHandle.seekToEndOfFile()

        let prompt = Self.buildPrompt(queuePath: learningQueueFile.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = projectPath
        process.arguments = [
            "-p", prompt,
            "--agent", "reviewer-BE",
            "--add-dir", projectPath.path,
            "--permission-mode", "bypassPermissions",
            "--output-format", "text",
            "--debug-file", debugURL.path,
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["CI"] = "1"
        env["TERM"] = "dumb"
        process.environment = env
        if let devNull = FileHandle(forReadingAtPath: "/dev/null") {
            process.standardInput = devNull
        }
        process.standardOutput = logHandle
        process.standardError = logHandle

        do { try process.run() } catch {
            lastResult = "spawn failed: \(error.localizedDescription)"
            try? logHandle.close()
            return false
        }
        isLearning = true
        lastResult = "Обучение запущено… (\(pendingDialogsCount) реплик)"

        process.terminationHandler = { [logDir, ts] proc in
            try? logHandle.close()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLearning = false
                let ok = proc.terminationStatus == 0
                let queueCleared = ok ? self.archiveQueue(logDir: logDir, ts: ts) : false
                self.lastResult = ok
                    ? "Обучение завершено. \(queueCleared ? "Очередь обнулена (бэкап рядом с логом). " : "")Смотри \(logURL.lastPathComponent)."
                    : "Обучение завершилось с ошибкой. Лог: \(logURL.lastPathComponent)."
            }
        }
        return true
    }

    /// Move consumed queue to `_learning/<ts>-consumed-queue.json` so it stays as audit trail
    /// but `pendingDialogsCount` returns to 0 → 🎓 disabled until new replies arrive.
    /// Возвращает true если файл реально переехал; false — если queue уже отсутствовал.
    private func archiveQueue(logDir: URL, ts: String) -> Bool {
        let queue = learningQueueFile
        guard FileManager.default.fileExists(atPath: queue.path) else { return false }
        let backup = logDir.appendingPathComponent("\(ts)-consumed-queue.json")
        do {
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.moveItem(at: queue, to: backup)
            return true
        } catch {
            NSLog("RuleLearningService.archiveQueue failed: \(error)")
            return false
        }
    }

    static func buildPrompt(queuePath: String) -> String {
        return """
        Задача: учись на ответах разработчиков на твои review-комментарии.

        Вход:
        - `\(queuePath)` — JSON-массив объектов `LearningDialog`:
          - mrRef, projectPath, mrNum, filePath, line
          - ourComment: что ты написал в коммент
          - authorReply: ответ автора (один или склеенные несколько)
          - resolved: тред зарезолвлен

        Алгоритм:
        1. Прочитай queue целиком (Read).
        2. Для каждого dialog оцени authorReply:
           - Если автор объясняет «это не баг» с обоснованием → возможный **false positive**. Сопоставь с твоим rules.yaml — найди правило по которому ты подсвечивал. Если правило слишком широкое — уточни pattern/exclude. Если это полностью неверно — добавь правило-исключение в категории `scope` или `process` с явным «DO NOT flag».
           - Если автор пишет «спасибо, пофиксил» / «учту» → правило сработало, ничего не меняем.
           - Если автор пишет про корпоративную/командную конвенцию → добавь новое правило в rules.yaml (с указанием severity, category, pattern, rationale, fix). Источник: ссылка на MR из mrRef.
           - Если ответ неясен (просто эмодзи / «ок» без контекста) → пропусти.
        3. Все правки делай в `.claude/agents/memory/reviewer-BE/rules.yaml` (путь относительно cwd текущего проекта) через Edit. НЕ перезаписывай весь файл. Если файла нет — создай (Write) с минимальным заголовком; rules.yaml должен оставаться валидным YAML.
        4. НЕ трогай playbooks.md и context.md.
        5. После всех правок выдай отчёт:
           ## Learning summary
           - Reviewed N dialogs
           - Added M new rules: …
           - Refined K rules: …
           - Skipped L (unclear replies): …
           - Conflicts (mark with ⚠): …

        ОГРАНИЧЕНИЯ:
        - Никаких HTTP / curl / поездок в GitLab — у тебя уже всё в queue.
        - Не публикуй ничего в MR.
        - Если предлагаешь рискованное изменение (удалить правило / переключить severity blocker→minor) — добавь комментарий `# REVIEW REQUIRED` рядом, не молча.
        - Если rules.yaml после твоих правок невалиден — откати свои правки.
        """
    }
}
