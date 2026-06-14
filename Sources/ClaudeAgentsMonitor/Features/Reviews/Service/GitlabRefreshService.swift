import Foundation

/// Lightweight, direct GitLab API client used by the «🔁 Refresh» button.
///
/// Bypasses the LLM entirely — we just need MR state + check whether the author
/// replied to every comment we left. Pure HTTP, runs in seconds.
///
/// Auth:
///   - HOST  — from `<project>/.claude/agents/memory/gitlab/vars.json`
///   - TOKEN — from macOS Keychain (`claude-agent-<projId>-gitlab` / TOKEN)
@MainActor
final class GitlabRefreshService {
    let queue: ReviewQueueService
    let projectPath: URL

    init(queue: ReviewQueueService, projectPath: URL) {
        self.queue = queue
        self.projectPath = projectPath
    }

    enum RefreshError: Error, LocalizedError {
        case noHost
        case noToken
        case http(Int, String)
        case parse(String)

        var errorDescription: String? {
            switch self {
            case .noHost: return "HOST не найден в gitlab/vars.json"
            case .noToken: return "TOKEN не найден в Keychain (claude-agent-<projId>-gitlab)"
            case .http(let s, let m): return "HTTP \(s): \(m)"
            case .parse(let m): return "Parse error: \(m)"
            }
        }
    }

    /// Result of refreshing one job — для UI feedback.
    struct JobOutcome {
        let jobId: String
        let archivedNow: Bool       // MR смержен/закрыт → job УДАЛЁН из очереди
        let canReReview: Bool       // на все наши треды дан ответ → подсветить ⟳
        let state: String?          // merged / closed / opened
        let learningDialogs: Int    // сколько новых пар «наш коммент → ответ автора» собрано
    }

    /// One thread we want to learn from — author replied to our comment.
    struct LearningDialog: Codable {
        let mrRef: String           // URL MR
        let projectPath: String     // waas/backend/portfolio-service
        let mrNum: Int
        let filePath: String?       // file.java
        let line: Int?              // 42
        let ourComment: String      // тело нашего inline-коммента
        let authorReply: String     // ответ автора (последний или склеенный)
        let resolved: Bool          // тред зарезолвлен
        let collectedAt: Date
    }

    // MARK: - Public

    func refreshAll() async -> [JobOutcome] {
        guard let host = readHost() else { return [] }
        guard let token = readToken() else { return [] }

        let activeJobs = queue.jobs.filter { !$0.archived }
        var outcomes: [JobOutcome] = []
        var allDialogs: [LearningDialog] = []
        for job in activeJobs {
            do {
                let (outcome, dialogs) = try await refresh(job: job, host: host, token: token)
                outcomes.append(outcome)
                allDialogs.append(contentsOf: dialogs)
            } catch {
                NSLog("GitlabRefreshService: \(job.id) failed: \(error.localizedDescription)")
            }
        }
        if !allDialogs.isEmpty {
            saveLearningDialogs(allDialogs)
        }
        return outcomes
    }

    /// Where learning dialogs accumulate. Cleared by the learning job after consumption.
    var learningQueueFile: URL {
        queue.reviewsDir.appendingPathComponent("learning-queue.json")
    }

    private func saveLearningDialogs(_ dialogs: [LearningDialog]) {
        // Merge with existing — keeps everything until the learning job clears it.
        var existing: [LearningDialog] = []
        if let data = try? Data(contentsOf: learningQueueFile) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            existing = (try? decoder.decode([LearningDialog].self, from: data)) ?? []
        }
        // Dedup by (mrRef, file:line, ourComment first 80 chars).
        // NEW dialogs OVERRIDE existing — иначе свежий authorReply (например автор дописал
        // аргумент почему «не баг») потерялся бы; держим самую актуальную версию пары.
        func key(_ d: LearningDialog) -> String {
            "\(d.mrRef)|\(d.filePath ?? ""):\(d.line ?? 0)|\(d.ourComment.prefix(80))"
        }
        var byKey: [String: LearningDialog] = [:]
        for d in existing { byKey[key(d)] = d }
        for d in dialogs { byKey[key(d)] = d }
        let merged = byKey.values.sorted { $0.collectedAt < $1.collectedAt }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(merged) {
            try? data.write(to: learningQueueFile, options: .atomic)
        }
    }

    // MARK: - Single job

    private func refresh(job: ReviewJob, host: String, token: String) async throws -> (JobOutcome, [LearningDialog]) {
        // multi-MR jobs: archive only when ALL its MRs merged/closed; canReReview only when ALL replied
        var allMerged = true
        var allReplied = true
        var lastState: String?
        var threadCounts: [String: (replied: Int, ourTotal: Int, allNotes: Int)] = [:]
        var mrMeta: [String: (author: String?, title: String?)] = [:]
        var dialogs: [LearningDialog] = []

        for mr in job.mrs {
            guard let (projectPath, mrNum) = parseGitLabRef(mr.ref) else {
                allMerged = false
                continue
            }
            let meta = try await fetchMRMeta(
                host: host, token: token, projectPath: projectPath, mrNum: mrNum
            )
            lastState = meta.state
            mrMeta[mr.ref] = (meta.author, meta.title)
            if meta.state != "merged" && meta.state != "closed" {
                allMerged = false
                let counts = try await countDiscussions(
                    host: host, token: token, projectPath: projectPath, mrNum: mrNum
                )
                threadCounts[mr.ref] = counts
                let replied = counts.ourTotal > 0 && counts.replied == counts.ourTotal
                if !replied { allReplied = false }
                // collect dialogs (only when there ARE replies to learn from)
                if counts.replied > 0 {
                    let mrDialogs = try await collectDialogs(
                        host: host, token: token, projectPath: projectPath, mrNum: mrNum, mrRef: mr.ref
                    )
                    dialogs.append(contentsOf: mrDialogs)
                }
            }
        }

        if allMerged && !job.mrs.isEmpty {
            // Полностью удаляем job — больше его никому показывать не нужно.
            queue.remove(job.id)
            return (JobOutcome(jobId: job.id, archivedNow: true, canReReview: false, state: lastState, learningDialogs: dialogs.count), dialogs)
        }

        queue.update(job.id) { j in
            j.lastRefreshAt = Date()
            j.liveMrState = lastState
            for i in j.mrs.indices {
                if let c = threadCounts[j.mrs[i].ref] {
                    j.mrs[i].threadsRepliedByAuthor = c.replied
                    j.mrs[i].totalNotesInMR = c.allNotes
                    j.mrs[i].commentsPosted = c.ourTotal
                }
                if let m = mrMeta[j.mrs[i].ref] {
                    if j.mrs[i].author == nil, let a = m.author { j.mrs[i].author = a }
                    if j.mrs[i].title == nil, let t = m.title { j.mrs[i].title = t }
                }
            }
            j.canReReview = allReplied
        }
        return (JobOutcome(jobId: job.id, archivedNow: false, canReReview: allReplied, state: lastState, learningDialogs: dialogs.count), dialogs)
    }

    /// Walk discussions one more time — for each OUR inline thread that got a reply, build a learning dialog.
    private func collectDialogs(host: String, token: String, projectPath: String, mrNum: Int, mrRef: String) async throws -> [LearningDialog] {
        let encoded = projectPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? projectPath
        let url = URL(string: "\(host)/api/v4/projects/\(encoded)/merge_requests/\(mrNum)/discussions?per_page=100")!
        let (data, response) = try await get(url: url, token: token)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        guard let discs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var out: [LearningDialog] = []
        for disc in discs {
            guard let notes = disc["notes"] as? [[String: Any]], let first = notes.first else { continue }
            let firstBody = (first["body"] as? String) ?? ""
            let hasPosition = (first["position"] as? [String: Any]) != nil
            guard firstBody.contains("_Posted by gitlab agent_"), hasPosition else { continue }

            // last note from someone not us
            let theirs = notes.filter { !( ($0["body"] as? String) ?? "").contains("_Posted by gitlab agent_") }
            guard !theirs.isEmpty else { continue }
            // склеиваем все reply'и автора в один текст
            let reply = theirs.compactMap { $0["body"] as? String }.joined(separator: "\n\n---\n\n")

            let pos = (first["position"] as? [String: Any]) ?? [:]
            let path = (pos["new_path"] as? String) ?? (pos["old_path"] as? String)
            let line = (pos["new_line"] as? Int) ?? (pos["old_line"] as? Int)
            let resolved = (first["resolved"] as? Bool) ?? false

            out.append(LearningDialog(
                mrRef: mrRef,
                projectPath: projectPath,
                mrNum: mrNum,
                filePath: path,
                line: line,
                ourComment: firstBody.replacingOccurrences(of: "_Posted by gitlab agent_", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
                authorReply: reply.trimmingCharacters(in: .whitespacesAndNewlines),
                resolved: resolved,
                collectedAt: Date()
            ))
        }
        return out
    }

    // MARK: - HTTP

    struct MRMeta {
        let state: String
        let author: String?
        let title: String?
    }

    private func fetchMRMeta(host: String, token: String, projectPath: String, mrNum: Int) async throws -> MRMeta {
        let encoded = projectPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? projectPath
        let url = URL(string: "\(host)/api/v4/projects/\(encoded)/merge_requests/\(mrNum)")!
        let (data, response) = try await get(url: url, token: token)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RefreshError.http((response as? HTTPURLResponse)?.statusCode ?? -1, "fetch MR")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = obj["state"] as? String else {
            throw RefreshError.parse("MR state")
        }
        let author = (obj["author"] as? [String: Any])?["username"] as? String
        let title = obj["title"] as? String
        return MRMeta(state: state, author: author, title: title)
    }

    /// Walks all discussions and returns:
    ///   - replied: # of OUR threads that got author reply (or are resolved)
    ///   - ourTotal: # of threads we started
    ///   - allNotes: total # of notes in the MR (everyone, including non-discussion system notes filtered out)
    private func countDiscussions(host: String, token: String, projectPath: String, mrNum: Int) async throws -> (replied: Int, ourTotal: Int, allNotes: Int) {
        let encoded = projectPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? projectPath
        let url = URL(string: "\(host)/api/v4/projects/\(encoded)/merge_requests/\(mrNum)/discussions?per_page=100")!
        let (data, response) = try await get(url: url, token: token)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RefreshError.http((response as? HTTPURLResponse)?.statusCode ?? -1, "discussions")
        }
        guard let discs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw RefreshError.parse("discussions")
        }
        var ourTotal = 0
        var replied = 0
        var allNotes = 0
        for disc in discs {
            guard let notes = disc["notes"] as? [[String: Any]], let first = notes.first else { continue }
            let firstBody = (first["body"] as? String) ?? ""
            let isOurs = firstBody.contains("_Posted by gitlab agent_")
            let hasPosition = (first["position"] as? [String: Any]) != nil
            let isOurSummary = isOurs && !hasPosition
            // Наш top-level summary не считаем ни в общий счётчик, ни в наши треды
            if isOurSummary { continue }
            // Все non-system notes от остальных (наших inline + чужих + ответов автора)
            for note in notes {
                let isSystem = (note["system"] as? Bool) ?? false
                if !isSystem { allNotes += 1 }
            }
            guard isOurs else { continue }
            ourTotal += 1
            if let resolved = first["resolved"] as? Bool, resolved {
                replied += 1
                continue
            }
            let ourLast = notes
                .filter { ($0["body"] as? String ?? "").contains("_Posted by gitlab agent_") }
                .compactMap { $0["created_at"] as? String }
                .max() ?? ""
            let theirLast = notes
                .filter { !( ($0["body"] as? String) ?? "").contains("_Posted by gitlab agent_") }
                .compactMap { $0["created_at"] as? String }
                .max() ?? ""
            if theirLast > ourLast {
                replied += 1
            }
        }
        return (replied: replied, ourTotal: ourTotal, allNotes: allNotes)
    }

    private func get(url: URL, token: String) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        return try await URLSession.shared.data(for: req)
    }

    // MARK: - Ref parsing

    /// Splits `https://gitlab.../waas/backend/portfolio-service/-/merge_requests/878` into
    /// `("waas/backend/portfolio-service", 878)`.
    static func parseGitLabRef(_ ref: String) -> (projectPath: String, mrNum: Int)? {
        guard ref.contains("/merge_requests/") || ref.contains("/-/merge_requests/") else { return nil }
        guard let url = URL(string: ref) else { return nil }
        let comps = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let mrIdx = comps.firstIndex(of: "merge_requests"),
              mrIdx + 1 < comps.count,
              let num = Int(comps[mrIdx + 1]) else { return nil }
        var projectParts = Array(comps[0..<mrIdx])
        if projectParts.last == "-" { projectParts.removeLast() }
        if projectParts.isEmpty { return nil }
        return (projectParts.joined(separator: "/"), num)
    }

    func parseGitLabRef(_ ref: String) -> (projectPath: String, mrNum: Int)? {
        Self.parseGitLabRef(ref)
    }

    // MARK: - Credentials

    private func readHost() -> String? {
        let varsURL = projectPath
            .appendingPathComponent(".claude/agents/memory/gitlab/vars.json")
        guard let data = try? Data(contentsOf: varsURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let host = dict["HOST"] else { return nil }
        return host
    }

    private func readToken() -> String? {
        let service = AgentVariablesService.keychainService(for: "gitlab")
        return AgentVariablesService.readKeychain(key: "TOKEN", service: service)
    }
}
