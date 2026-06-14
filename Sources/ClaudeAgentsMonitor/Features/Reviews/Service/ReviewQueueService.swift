import Foundation

/// Persistent FIFO queue of review jobs for a project.
/// State lives in `<project>/.claude/reviews/queue.json`; per-job logs in
/// `<project>/.claude/reviews/<jobId>/`.
@MainActor
final class ReviewQueueService: ObservableObject {
    @Published private(set) var jobs: [ReviewJob] = []

    private let projectRoot: URL

    init(projectRoot: URL) {
        self.projectRoot = projectRoot
        ensureDirs()
        load()
        reconcileOrphans()
    }

    /// Find jobs marked `running` whose claude process no longer exists
    /// (CAM was restarted while they ran). Parse their log, mark completed.
    private func reconcileOrphans() {
        for idx in jobs.indices {
            let job = jobs[idx]
            guard job.status == .running, let pid = job.pid else { continue }
            // kill(pid, 0) — 0 if alive (with permission), ESRCH if process not found
            let alive = (kill(pid, 0) == 0) || (errno == EPERM) // EPERM = exists but we can't signal it
            if alive { continue }

            // Process is gone — promote orphan to completed.
            let logURL = logFile(for: job.id)
            let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let report: String = {
                if let r = logText.range(of: "## MR ", options: .backwards) {
                    return String(logText[r.lowerBound...])
                }
                return logText
            }()
            try? report.write(to: resultFile(for: job.id), atomically: true, encoding: .utf8)
            let findings = ReviewParser.parse(report)

            var copy = job
            copy.status = .completed
            copy.finishedAt = Date()
            copy.pid = nil
            ReviewParser.apply(findings, to: &copy)
            jobs[idx] = copy
        }
        save()
    }

    var reviewsDir: URL {
        projectRoot.appendingPathComponent(".claude/reviews", isDirectory: true)
    }

    var queueFile: URL {
        reviewsDir.appendingPathComponent("queue.json")
    }

    func jobDir(_ jobId: String) -> URL {
        reviewsDir.appendingPathComponent(jobId, isDirectory: true)
    }

    func logFile(for jobId: String) -> URL {
        jobDir(jobId).appendingPathComponent("log.txt")
    }

    func resultFile(for jobId: String) -> URL {
        jobDir(jobId).appendingPathComponent("result.md")
    }

    // MARK: - CRUD

    func enqueue(_ job: ReviewJob) {
        jobs.append(job)
        ensureJobDir(job.id)
        save()
    }

    func update(_ jobId: String, _ mutate: (inout ReviewJob) -> Void) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        // Explicit copy → mutate → reassign — triggers @Published reliably for SwiftUI.
        var job = jobs[idx]
        mutate(&job)
        jobs[idx] = job
        save()
    }

    func remove(_ jobId: String) {
        jobs.removeAll { $0.id == jobId }
        try? FileManager.default.removeItem(at: jobDir(jobId))
        save()
    }

    /// Create a re-review job — same MR refs as parent, marked as continuation.
    /// Resolve-threads in re-review is implicit (built into the prompt).
    /// Pass `note` to override parent's note for this re-review (fresh context for the agent).
    func enqueueReReview(of parent: ReviewJob, note: String? = nil) -> ReviewJob {
        let freshMrs = parent.mrs.map { mr in
            ReviewMR(ref: mr.ref, resolvedUrl: mr.resolvedUrl, title: mr.title, clsKey: mr.clsKey)
        }
        let job = ReviewJob(
            id: Self.makeId(),
            projectPath: parent.projectPath,
            mrs: freshMrs,
            status: .queued,
            note: note ?? parent.note,
            parentJobId: parent.id,
            startedAt: Date(),
            finishedAt: nil,
            pid: nil,
            logFile: nil
        )
        enqueue(job)
        return job
    }

    /// Active = queued / running / paused (ждут продолжения).
    var activeJobs: [ReviewJob] {
        jobs.filter { !$0.archived && ($0.status == .queued || $0.status == .running || $0.status == .paused) }
    }

    /// Recent completed jobs (only non-archived).
    var recentCompletedJobs: [ReviewJob] {
        jobs
            .filter { !$0.archived }
            .filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    // MARK: - Persistence

    private func ensureDirs() {
        try? FileManager.default.createDirectory(at: reviewsDir, withIntermediateDirectories: true)
    }

    private func ensureJobDir(_ id: String) {
        try? FileManager.default.createDirectory(at: jobDir(id), withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: queueFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ReviewJob].self, from: data) {
            jobs = decoded
        }
    }

    private func save() {
        ensureDirs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(jobs)
            try data.write(to: queueFile, options: .atomic)
        } catch {
            NSLog("ReviewQueueService.save failed: \(error)")
        }
    }

    /// Generate a sortable, filesystem-friendly id.
    static func makeId() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
