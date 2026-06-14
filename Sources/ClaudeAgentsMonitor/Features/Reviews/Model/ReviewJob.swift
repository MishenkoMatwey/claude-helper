import Foundation

/// Verdict for a single MR after review. `pending` = job не закончен.
enum ReviewVerdict: String, Codable, CaseIterable {
    case pending
    case green    // 0 blockers, ≤2 minor — можно мержить
    case yellow   // 0 blockers, есть major или 3+ minor — есть замечания
    case red      // ≥1 blocker — мержить нельзя
    case failed   // тех-ошибка во время прогона

    /// Map from finding counts produced by reviewer.
    /// - blockers > 0      → red
    /// - major > 0         → yellow (отрисовывается оранжевым)
    /// - только minors / 0 → green
    static func fromFindings(blockers: Int, major: Int, minor: Int) -> ReviewVerdict {
        if blockers > 0 { return .red }
        if major > 0 { return .yellow }
        return .green
    }
}

/// One MR inside a job. Counts and verdict filled by parser once review completes.
struct ReviewMR: Identifiable, Codable, Hashable {
    var id: String { ref }            // ref = URL or "!N" / "#N"
    var ref: String                   // как ввёл пользователь
    var resolvedUrl: String?          // полный URL после нормализации (если получилось)
    var title: String?
    var clsKey: String?               // CLS-XXXX из title/branch/body
    var author: String?               // username автора MR (из отчёта или GitLab API)
    var blockers: Int = 0
    var major: Int = 0
    var minor: Int = 0
    var commentsPosted: Int = 0
    var threadsRepliedByAuthor: Int = 0  // refresh: сколько наших threads получили ответ автора (или зарезолвлены)
    var totalNotesInMR: Int = 0          // refresh: общее число всех notes в MR (наши + чужие + reply'и)
    var verdict: ReviewVerdict = .pending
    var error: String?                // тех-ошибка для этого MR (если только этот зафейлился)

    init(ref: String, resolvedUrl: String? = nil, title: String? = nil, clsKey: String? = nil,
         author: String? = nil,
         blockers: Int = 0, major: Int = 0, minor: Int = 0, commentsPosted: Int = 0,
         threadsRepliedByAuthor: Int = 0, totalNotesInMR: Int = 0,
         verdict: ReviewVerdict = .pending, error: String? = nil) {
        self.ref = ref
        self.resolvedUrl = resolvedUrl
        self.title = title
        self.clsKey = clsKey
        self.author = author
        self.blockers = blockers
        self.major = major
        self.minor = minor
        self.commentsPosted = commentsPosted
        self.threadsRepliedByAuthor = threadsRepliedByAuthor
        self.totalNotesInMR = totalNotesInMR
        self.verdict = verdict
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ref = try c.decode(String.self, forKey: .ref)
        self.resolvedUrl = try c.decodeIfPresent(String.self, forKey: .resolvedUrl)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.clsKey = try c.decodeIfPresent(String.self, forKey: .clsKey)
        self.author = try c.decodeIfPresent(String.self, forKey: .author)
        self.blockers = try c.decodeIfPresent(Int.self, forKey: .blockers) ?? 0
        self.major = try c.decodeIfPresent(Int.self, forKey: .major) ?? 0
        self.minor = try c.decodeIfPresent(Int.self, forKey: .minor) ?? 0
        self.commentsPosted = try c.decodeIfPresent(Int.self, forKey: .commentsPosted) ?? 0
        self.threadsRepliedByAuthor = try c.decodeIfPresent(Int.self, forKey: .threadsRepliedByAuthor) ?? 0
        self.totalNotesInMR = try c.decodeIfPresent(Int.self, forKey: .totalNotesInMR) ?? 0
        self.verdict = try c.decodeIfPresent(ReviewVerdict.self, forKey: .verdict) ?? .pending
        self.error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

enum ReviewJobStatus: String, Codable {
    case queued
    case running
    case paused      // claude процесс упал/убит, но job ждёт resume (rate-limit или manual pause)
    case completed
    case cancelled
    case failed
}

/// Single batch of MRs reviewed together. If `mrs.count > 1` — orchestrator
/// understands their relationship (one feature across services etc).
struct ReviewJob: Identifiable, Codable {
    var id: String                    // ISO timestamp slug (sortable + stable)
    var projectPath: String           // абсолютный путь проекта (для filter в UI)
    var mrs: [ReviewMR]
    var status: ReviewJobStatus
    var note: String?                 // свободный комментарий пользователя из формы
    var parentJobId: String?          // если это re-review — id предыдущего job по тем же MR
    var startedAt: Date
    var finishedAt: Date?
    var pid: Int32?                   // PID запущенного claude-процесса (для cancel)
    var logFile: String?              // путь к stdout-логу claude
    var claudeSessionId: String?      // uuid сессии для --resume после паузы
    var pauseReason: String?          // напр. "rate_limit" или "manual"
    // refresh-флаги — обновляются кнопкой 🔁 в карточке (через GitlabRefreshService)
    var archived: Bool = false        // если MR смержен/закрыт — прячем job из UI
    var canReReview: Bool = false     // автор ответил на ВСЕ наши треды → подсветить ⟳
    var lastRefreshAt: Date?
    var liveMrState: String?          // last known: "opened" / "merged" / "closed"

    var displayTitle: String {
        if mrs.count == 1 { return mrs[0].title ?? mrs[0].ref }
        return "\(mrs.count) MRs"
    }

    /// Composite verdict — наихудший из всех MR'ов.
    var overallVerdict: ReviewVerdict {
        if status == .failed { return .failed }
        if status != .completed { return .pending }
        let verdicts = mrs.map(\.verdict)
        if verdicts.contains(.red) { return .red }
        if verdicts.contains(.yellow) { return .yellow }
        if verdicts.contains(.failed) { return .failed }
        return .green
    }

    var totalBlockers: Int { mrs.reduce(0) { $0 + $1.blockers } }
    var totalMajor: Int { mrs.reduce(0) { $0 + $1.major } }
    var totalMinor: Int { mrs.reduce(0) { $0 + $1.minor } }
    var totalComments: Int { mrs.reduce(0) { $0 + $1.commentsPosted } }
    var totalThreadsReplied: Int { mrs.reduce(0) { $0 + $1.threadsRepliedByAuthor } }

    init(id: String, projectPath: String, mrs: [ReviewMR], status: ReviewJobStatus,
         note: String? = nil, parentJobId: String? = nil,
         startedAt: Date, finishedAt: Date? = nil,
         pid: Int32? = nil, logFile: String? = nil,
         claudeSessionId: String? = nil, pauseReason: String? = nil,
         archived: Bool = false, canReReview: Bool = false,
         lastRefreshAt: Date? = nil, liveMrState: String? = nil) {
        self.id = id
        self.projectPath = projectPath
        self.mrs = mrs
        self.status = status
        self.note = note
        self.parentJobId = parentJobId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.pid = pid
        self.logFile = logFile
        self.claudeSessionId = claudeSessionId
        self.pauseReason = pauseReason
        self.archived = archived
        self.canReReview = canReReview
        self.lastRefreshAt = lastRefreshAt
        self.liveMrState = liveMrState
    }

    /// Forgiving decoder — silently fills missing keys with defaults so old queue.json layouts
    /// keep working after model evolution.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.projectPath = try c.decode(String.self, forKey: .projectPath)
        self.mrs = try c.decode([ReviewMR].self, forKey: .mrs)
        self.status = try c.decode(ReviewJobStatus.self, forKey: .status)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.parentJobId = try c.decodeIfPresent(String.self, forKey: .parentJobId)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        self.pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        self.logFile = try c.decodeIfPresent(String.self, forKey: .logFile)
        self.claudeSessionId = try c.decodeIfPresent(String.self, forKey: .claudeSessionId)
        self.pauseReason = try c.decodeIfPresent(String.self, forKey: .pauseReason)
        self.archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        self.canReReview = try c.decodeIfPresent(Bool.self, forKey: .canReReview) ?? false
        self.lastRefreshAt = try c.decodeIfPresent(Date.self, forKey: .lastRefreshAt)
        self.liveMrState = try c.decodeIfPresent(String.self, forKey: .liveMrState)
    }
}
