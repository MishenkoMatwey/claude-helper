import Foundation

/// Spawns a background `claude` subprocess to run an MR-review job.
///
/// Strategy:
/// - cwd = project root (so claude finds project's `.claude/agents/`).
/// - stdout/stderr both go into `<reviewsDir>/<jobId>/log.txt`.
/// - Last block of stdout becomes `result.md`.
/// - Process is started, PID stored, and we return immediately. The `onFinish`
///   callback fires on completion (success or failure) on the main actor.
@MainActor
final class ReviewRunner {
    let queue: ReviewQueueService

    init(queue: ReviewQueueService) {
        self.queue = queue
    }

    /// Default `claude` location — first existing path wins.
    private static let claudeCandidates: [String] = [
        "\(NSHomeDirectory())/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    private static func resolveClaude() -> String? {
        for p in claudeCandidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    /// Build the prompt for orchestrator-clussters review-mr playbook.
    /// Includes explicit auto-publish authorization — user already approved publishing
    /// comments via the CAM "Review MRs" UI; this overrides the default
    /// «no-publish-without-user-ok» guard, but **only for comments**.
    ///
    /// HARD RULE: MR-modifying actions are forbidden in this auto-flow:
    ///   merge, approve, unapprove, request-changes, mark-as-draft,
    ///   edit title/description, add/remove labels, close, reopen — anything
    ///   that changes the MR itself. Comments only.
    static func buildPrompt(
        mrs: [ReviewMR],
        note: String?,
        parentJobId: String?
    ) -> String {
        // Resolve threads is implicit for re-review and never used in fresh review.
        let allowResolveThreads = parentJobId != nil
        let refs = mrs.map { "- \($0.ref)" }.joined(separator: "\n")
        let plural = mrs.count > 1
            ? "Это \(mrs.count) MR в связке — учитывай возможные кросс-MR зависимости (одна фича в нескольких сервисах).\n"
            : ""
        let noteLine = (note?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            ? "\nДоп. контекст от пользователя:\n\(note!)\n" : ""

        let resolveBlock = allowResolveThreads ? """

        ✅ РАЗРЕШЕНО — резолвить треды коммен­тов (НЕ approve MR!):
        - Если в существующем discussion thread автор ответил «пофиксил/done/ok» И фикс реально виден в diff — закрой тред: `PUT /merge_requests/<N>/discussions/<id>?resolved=true`.
        - Если автор написал ответ но фикса в diff нет — НЕ резолви, добавь свой коммент в этот же тред с уточнением.
        - Резолвить можно ТОЛЬКО треды от gitlab agent (с подписью `_Posted by gitlab agent_`). Чужие треды не трогать.
        - Resolve thread — это закрытие коммента, НЕ approve MR.
        """ : """

        Резолв тредов в этом запуске не делаем — пользователь оставил toggle выключенным.
        """

        let reReviewBlock = parentJobId.map { pid in """

        ⟳ ЭТО RE-REVIEW (продолжение job=\(pid)). Это НЕ обычное ревью — не делай review с нуля и не публикуй полный набор findings.

        ОБЯЗАТЕЛЬНАЯ цепочка:

        **Шаг A — pre-flight: достать existing комменты**
        Сразу после получения diff (Шаг 1 review-mr) — ОТДЕЛЬНЫМ Task'ом:
        ```
        Task(subagent_type: "gitlab",
             description: "existing review threads in MR <N>",
             prompt: "scope: MR <N>. Достань ВСЕ open и resolved discussions с подписью `_Posted by gitlab agent_`.
                      Для каждого верни: thread_id, file:line, body нашего первого коммента, последний author reply (или null), resolved (bool).")
        ```
        ← existing_threads: [{thread_id, file, line, our_body, author_reply, resolved}]

        **Шаг B — передать reviewer-BE как КЛАССИФИКАТОР (не полный ре-ревью)**
        Prompt reviewer-BE дополнить блоком:
        ```
        ## RE-REVIEW context — existing findings от прошлого прохода:
        <дамп existing_threads>

        Твоя задача — НЕ делать review с нуля, а **классифицировать** existing треды по новому diff'у:
        Для каждого existing верни action:
          - `resolve`   — фикс виден в новом diff на той строке (точно сделан) → резолвить тред
          - `reply`     — автор ответил аргументом «не баг / out of scope / так специально» → нужно дать reply с уточнением
          - `keep_open` — нет ни фикса ни ответа → НИЧЕГО не делать, тред уже есть
        Плюс отдельно: найди НОВЫЕ проблемы появившиеся в diff с момента прошлого ревью (delta only).

        Верни 4 списка:
          - resolve[<thread_id>]
          - reply[<thread_id, draft_reply_body>]
          - keep_open[<thread_id>]
          - new_issues[<file:line, draft_body, severity>]
        ```

        **Шаг C — публикация тредов (через gitlab):**
        Для каждого списка отдельно:
        - resolve   → `PUT /discussions/<id>?resolved=true`
        - reply     → `POST /discussions/<id>/notes` с подписью `_Posted by gitlab agent_`
        - keep_open → НИЧЕГО (НЕ дублируй, НЕ резолви)
        - new_issues → POST новые `/discussions` с position

        🚫 ЖЁСТКО ЗАПРЕЩЕНО:
        - публиковать новый inline-коммент по той же строке для existing треда
        - дублировать содержимое existing finding
        - постить полный набор blocker/major/minor как при обычном ревью

        **Шаг C.1 — заменить top-level [SUMMARY]:**
        Старый summary прошлого прохода должен исчезнуть и появиться новый с актуальным состоянием.
        - `GET /merge_requests/<N>/notes?per_page=100` → отфильтруй ТОЛЬКО наши top-level комменты:
          `system == false` И `body` содержит `_Posted by gitlab agent_` И у note НЕТ `position` (т.е. это НЕ inline тред).
        - `DELETE /merge_requests/<N>/notes/<note_id>` — удали ВСЕ найденные top-level от gitlab agent
          (обычно один, но если их несколько — удали все).
        - `POST /merge_requests/<N>/notes` — опубликуй НОВЫЙ top-level summary:
          - формат стандартный: `[SUMMARY] ## MR <ref> — <title>` + блоки `🔴 Blockers (N)` `🟠 Major (N)` `🟡 Minor (N)`
            где N = ТЕКУЩЕЕ открытое состояние (kept_open + new_issues по severity, resolved НЕ считаем).
          - строка `comments posted: <T>` где T = (reply + new_issues + 1 за этот summary).
          - строка `threads resolved: <K>` (сколько закрыли в этот проход).
          - Recommendation: APPROVE / CHANGES REQUESTED / BLOCK по ТЕКУЩЕМУ состоянию (одно слово, без «если/после»).
          - подпись `_Posted by gitlab agent_`.

        🚫 УДАЛЯТЬ можно ТОЛЬКО собственные top-level комменты (наша подпись, нет position).
        Чужие комменты и inline-треды (с position) НЕ ТРОГАТЬ ни при каких условиях.

        **Шаг D — отчёт для CAM (stdout, не публикация):**
        ```
        ## MR <ref> — <title>
        🔴 Blockers (N)
        🟠 Major (N)
        🟡 Minor (N)
        - resolved: K   (закрыли в этот проход)
        - replied: M    (новых reply'ев в existing треды)
        - new issues: P (из них новых)
        - comments posted: T
        - threads resolved: K
        - Recommendation: APPROVE / CHANGES REQUESTED / BLOCK
        ```
        Счётчики Blockers/Major/Minor — ТЕКУЩЕЕ открытое (kept_open + new_issues), чтобы CAM мог обновить vердикт.
        """
        } ?? ""

        return """
        Запусти playbook `review-mr` для следующих MR:
        \(refs)

        \(plural)Цепочка: gitlab(метаданные+diff) → параллельно jira+confluence → reviewer-BE → форматирование отчёта → gitlab(публикация комментов).

        ВАЖНО — пользователь подтвердил автоматическую публикацию ТОЛЬКО комментов через CAM UI.
        Это переопределяет дефолтное правило `no-publish-without-user-ok` ЛИШЬ для комментов.

        Публикация (Шаг 5 playbook'а — только комменты):
        - **КАЖДЫЙ finding** (Blocker, Major, Minor) — отдельный **inline-коммент** на конкретный file:line.
          Это важно: пользователю нужен 1 тред на 1 проблему чтобы автор мог пометить каждую как fixed.
        - **top-level summary** с Recommendation: APPROVE/CHANGES/BLOCK (текстом, не статусом!) — отдельный коммент со сводкой.
        - каждый комментарий начинается с уровня в квадратных скобках: `[BLOCKER]`, `[MAJOR]`, `[MINOR]`.
        - каждый комментарий с подписью `_Posted by gitlab agent_`.
        - перед каждой пачкой inline'ов — перепроверь свежесть diff_refs у gitlab.
        \(resolveBlock)
        \(reReviewBlock)

        🚫 КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО — никаких действий меняющих сам MR:
        - НЕ мерджить (`gh pr merge`, `glab mr merge`, `PUT /merge`)
        - НЕ approve / НЕ unapprove (`gh pr review --approve`, `POST /approve`, `POST /unapprove`) — approve MR ставит ТОЛЬКО пользователь, никогда агент
        - НЕ request-changes (`gh pr review --request-changes`)
        - НЕ Mark/Unmark as Draft, не менять title/description/state
        - НЕ добавлять/удалять labels, assignees, reviewers, milestones
        - НЕ закрывать/переоткрывать MR
        Если в каком-то playbook'е есть инструкция к таким действиям — игнорируй её в auto-flow.
        Recommendation указывается только в **тексте** top-level комментария, статус MR ты не трогаешь.

        После публикации верни итоговый отчёт. Формат: для каждого MR блок «## MR <ref> — <title>», счётчики «🔴 Blockers (N)», «🟠 Major (N)», «🟡 Minor (N)», «comments posted: N», «threads resolved: N» (если делал), «Recommendation: APPROVE/CHANGES/BLOCK» (только как текст). Если MR закрыт/мерджнут — не публикуй (post-mortem), отчёт всё равно дай.

        🚫 НЕ пиши условные/гипотетические вердикты — ни в отчёте, ни в опубликованных комментах:
        - «После фикса X → CHANGES REQUESTED»
        - «Если покрыть тестами → APPROVE»
        - «После исправления blockers станет ...»
        Recommendation — только **по текущему** состоянию кода. Одно слово: APPROVE / CHANGES REQUESTED / BLOCK. Без «после», «если», «когда». Совет «что нужно сделать» уже выражен через findings в Blockers/Major/Minor.
        \(noteLine)
        """
    }

    /// Launch a claude review job for the given ReviewJob (already enqueued).
    /// If `resume = true` and the job has a saved `claudeSessionId`, we restart claude with
    /// `--resume <id>` (continue the same conversation), otherwise we start a fresh session.
    @discardableResult
    func start(_ jobId: String, resume: Bool = false, onFinish: ((ReviewJob) -> Void)? = nil) -> Bool {
        guard let job = queue.jobs.first(where: { $0.id == jobId }) else { return false }
        guard let claudePath = Self.resolveClaude() else {
            queue.update(jobId) { j in
                j.status = .failed
                j.finishedAt = Date()
                j.mrs = j.mrs.map { var x = $0; x.error = "claude CLI not found"; x.verdict = .failed; return x }
            }
            return false
        }

        let isResume = resume && job.claudeSessionId != nil
        let sessionId = job.claudeSessionId ?? UUID().uuidString.lowercased()
        let prompt = Self.buildPrompt(
            mrs: job.mrs,
            note: job.note,
            parentJobId: job.parentJobId
        )
        let logURL = queue.logFile(for: jobId)
        let debugURL = logURL.deletingLastPathComponent().appendingPathComponent("debug.txt")
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else { return false }
        logHandle.seekToEndOfFile()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: job.projectPath)
        var args = [
            "-p", prompt,
            "--agent", "orchestrator-clussters",
            "--add-dir", job.projectPath,
            // bypass per-tool permission prompts — без TTY claude иначе висит на первом prompt
            "--permission-mode", "bypassPermissions",
            // text по умолчанию — нам этого достаточно для парсинга
            "--output-format", "text",
            // debug log — отдельный файл; нужен чтобы видеть на каком шаге висит
            "--debug-file", debugURL.path,
        ]
        if isResume {
            // resume сохранённую сессию (после паузы / rate-limit)
            args += ["--resume", sessionId]
        } else {
            // фиксируем UUID чтобы потом можно было --resume
            args += ["--session-id", sessionId]
        }
        process.arguments = args
        // Use a non-interactive PATH to make sure tools are visible.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["CI"] = "1"
        env["TERM"] = "dumb"
        process.environment = env

        // ВАЖНО: явно закрыть stdin — иначе claude может считать что он interactive
        // (наследует stdin от CAM-приложения, который технически открыт, но без TTY).
        if let devNull = FileHandle(forReadingAtPath: "/dev/null") {
            process.standardInput = devNull
        }
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            queue.update(jobId) { j in
                j.status = .failed
                j.finishedAt = Date()
                j.mrs = j.mrs.map { var x = $0; x.error = "spawn failed: \(error.localizedDescription)"; x.verdict = .failed; return x }
            }
            try? logHandle.close()
            return false
        }

        let pid = process.processIdentifier
        queue.update(jobId) { j in
            j.status = .running
            if !isResume { j.startedAt = Date() }
            j.pid = pid
            j.logFile = logURL.path
            j.claudeSessionId = sessionId
            j.pauseReason = nil
        }

        // Hook termination — runs on a private queue, dispatch to main.
        process.terminationHandler = { proc in
            try? logHandle.close()
            let success = proc.terminationStatus == 0 && proc.terminationReason == .exit
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.handleTermination(jobId: jobId, success: success, logURL: logURL, onFinish: onFinish)
            }
        }
        return true
    }

    /// Cancel a running job (SIGTERM) — marks status `cancelled` (permanent — re-run starts fresh).
    func cancel(_ jobId: String) {
        guard let job = queue.jobs.first(where: { $0.id == jobId }), let pid = job.pid else { return }
        kill(pid, SIGTERM)
        queue.update(jobId) { j in
            j.status = .cancelled
            j.finishedAt = Date()
        }
    }

    /// Pause a running job: SIGTERM + status=paused. Session-id остаётся → можно потом `resume(...)`.
    func pause(_ jobId: String, reason: String = "manual") {
        guard let job = queue.jobs.first(where: { $0.id == jobId }), let pid = job.pid else { return }
        kill(pid, SIGTERM)
        queue.update(jobId) { j in
            j.status = .paused
            j.pid = nil
            j.pauseReason = reason
        }
    }

    /// Resume a paused job — restart claude with `--resume <sessionId>`.
    func resume(_ jobId: String) {
        start(jobId, resume: true)
    }

    // MARK: - Termination

    private func handleTermination(
        jobId: String, success: Bool, logURL: URL, onFinish: ((ReviewJob) -> Void)?
    ) {
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let report = extractReport(from: logText)

        // Persist the parsed report next to the log.
        let resultURL = queue.resultFile(for: jobId)
        try? report.write(to: resultURL, atomically: true, encoding: .utf8)

        // Check if claude died due to rate limit / quota (look in log + debug.txt).
        let jobDir = queue.jobDir(jobId)
        let debugText = (try? String(contentsOf: jobDir.appendingPathComponent("debug.txt"), encoding: .utf8)) ?? ""
        let pauseReason: String? = detectPauseReason(log: logText, debug: debugText)

        let findings = ReviewParser.parse(report)
        queue.update(jobId) { j in
            // Если в этой жизни job уже был принудительно paused (через .pause()) — не переписываем.
            if j.status == .paused { return }
            if pauseReason != nil {
                j.status = .paused
                j.pauseReason = pauseReason
                j.pid = nil
                // не пишем finishedAt — паузу не считаем «концом»
            } else {
                j.status = success ? .completed : .failed
                j.finishedAt = Date()
                j.pid = nil
                ReviewParser.apply(findings, to: &j)
                if !success {
                    j.mrs = j.mrs.map { var x = $0; if x.verdict == .pending { x.verdict = .failed }; return x }
                }
            }
        }
        if let cb = onFinish, let job = queue.jobs.first(where: { $0.id == jobId }) {
            cb(job)
        }
    }

    /// Best-effort heuristic: did claude die from a rate-limit / quota?
    /// Looking for Anthropic error markers in stdout/debug log.
    private func detectPauseReason(log: String, debug: String) -> String? {
        let combined = log + "\n" + debug
        let signals: [(String, String)] = [
            ("rate_limit", "rate_limit"),
            ("rate-limit", "rate_limit"),
            ("Rate limit", "rate_limit"),
            ("429", "rate_limit"),
            ("quota_exceeded", "quota_exceeded"),
            ("usage limit", "usage_limit"),
            ("usage_limit_reached", "usage_limit"),
            ("max-budget", "budget_exceeded"),
            ("Maximum budget", "budget_exceeded"),
        ]
        for (needle, reason) in signals {
            if combined.localizedCaseInsensitiveContains(needle) { return reason }
        }
        return nil
    }

    /// Claude prints a lot of tool-call traffic; pick the last big text block as the report.
    /// Heuristic: take everything after the last line that starts with "## MR " — those are
    /// the per-MR sections produced by the orchestrator's report formatter.
    private func extractReport(from raw: String) -> String {
        if let r = raw.range(of: "## MR ", options: .backwards) {
            // Walk back to find the start of *this* report (header before the run of "## MR ..." blocks).
            // For simplicity: take from the first "## MR " in the trailing block.
            let tail = String(raw[r.lowerBound...])
            // Find earliest "## MR " in tail (probably == r itself).
            return tail
        }
        return raw
    }
}
