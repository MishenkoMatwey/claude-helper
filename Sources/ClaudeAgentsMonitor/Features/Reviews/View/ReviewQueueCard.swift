import SwiftUI
import AppKit

/// Card on ProjectDetailView. Shows queue button + active + recent jobs.
struct ReviewQueueCard: View {
    let projectPath: String

    @StateObject private var queue: ReviewQueueService
    @StateObject private var runnerHost: RunnerHost
    @StateObject private var learning: RuleLearningService
    @State private var showNewSheet = false
    @State private var reReviewParent: ReviewJob?
    @State private var revealJobId: String?
    @State private var isRefreshing = false
    @State private var refreshSummary: String?
    private let refreshService: GitlabRefreshService

    init(projectPath: String) {
        self.projectPath = projectPath
        let svc = ReviewQueueService(projectRoot: URL(fileURLWithPath: projectPath))
        _queue = StateObject(wrappedValue: svc)
        _runnerHost = StateObject(wrappedValue: RunnerHost(queue: svc))
        _learning = StateObject(wrappedValue: RuleLearningService(projectPath: URL(fileURLWithPath: projectPath)))
        self.refreshService = GitlabRefreshService(
            queue: svc, projectPath: URL(fileURLWithPath: projectPath)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            DesignSectionHeader(
                title: "MR Reviews",
                subtitle: subtitle,
                icon: "checkmark.shield.fill",
                trailing: AnyView(
                    HStack(spacing: 8) {
                        if isRefreshing {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await runRefresh() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.callout.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .help("Обновить: состояние MR-ов + ответы автора. Смерженные удаляются. Ответы собираются для обучения 🎓.")
                            .disabled(queue.jobs.isEmpty)
                        }
                        // Learning button: визуально подсвечен, когда есть что переваривать.
                        let pending = learning.pendingDialogsCount
                        Button {
                            learning.start()
                        } label: {
                            HStack(spacing: 3) {
                                if learning.isLearning {
                                    ProgressView().controlSize(.small).scaleEffect(0.55)
                                } else {
                                    Image(systemName: "graduationcap.fill")
                                        .font(.callout)
                                }
                                if pending > 0 {
                                    Text("\(pending)").font(.caption2.monospaced())
                                }
                            }
                            .foregroundStyle(pending > 0 ? .green : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(learning.isLearning || pending == 0)
                        .help(pending > 0
                              ? "🎓 Обучить reviewer-BE на \(pending) ответах автора — обновит rules.yaml."
                              : "Нет ответов автора в очереди обучения. Сначала сделай Refresh.")
                        Button {
                            showNewSheet = true
                        } label: {
                            Label("Review MRs", systemImage: "plus.circle.fill")
                                .font(DS.Typo.captionMedium)
                        }
                        .buttonStyle(GhostButtonStyle(tint: DS.Color.success))
                        .help("Start a new MR review (one or many)")
                    }
                )
            )

            if let refreshSummary {
                Text(refreshSummary)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let learnResult = learning.lastResult {
                Text(learnResult)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if queue.jobs.isEmpty {
                Text("Пока пусто. Нажми «Review MRs» — вставь номера/ссылки и стартуй.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                if !queue.activeJobs.isEmpty {
                    Text("В работе").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(queue.activeJobs) { job in
                        ReviewJobRow(
                            job: job,
                            onPrimary: { primaryAction(for: job) },
                            onReveal: { reveal(job.id) },
                            onRemove: { queue.remove(job.id) }
                        )
                    }
                }
                if !queue.recentCompletedJobs.isEmpty {
                    if !queue.activeJobs.isEmpty {
                        Divider().padding(.vertical, 2)
                    }
                    Text("Завершённые").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(queue.recentCompletedJobs.prefix(10)) { job in
                        ReviewJobRow(
                            job: job,
                            onPrimary: { primaryAction(for: job) },
                            onReveal: { reveal(job.id) },
                            onRemove: { queue.remove(job.id) }
                        )
                    }
                }
            }
        }
        .designCard()
        .sheet(isPresented: $showNewSheet) {
            NewReviewSheet(queue: queue, projectPath: projectPath, onStart: { job in
                runnerHost.runner.start(job.id)
            })
        }
        .sheet(item: $reReviewParent) { parent in
            ReReviewSheet(queue: queue, parent: parent, onStart: { job in
                runnerHost.runner.start(job.id)
            })
        }
    }

    private var subtitle: String {
        let act = queue.activeJobs.count
        let done = queue.recentCompletedJobs.count
        if act == 0 && done == 0 { return "0 active" }
        return "\(act) active · \(done) completed"
    }

    private func reveal(_ jobId: String) {
        let path = queue.jobDir(jobId)
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    /// Unified primary action: depends on current job status.
    /// - running   → pause (SIGTERM, status=paused, можно потом resume)
    /// - paused    → resume (start --resume <sessionId>)
    /// - completed → open ReReviewSheet → запускается полноценный re-review
    ///   (parentJobId сохраняется → классификатор existing-тредов + delta-only,
    ///   resolve тредов разрешён, старый [SUMMARY] заменяется новым).
    ///   Старый job ОСТАЁТСЯ в истории «Завершённые».
    /// - failed/cancelled → fresh review с теми же MR refs, старый job удаляется
    /// - queued    → no-op
    private func primaryAction(for job: ReviewJob) {
        switch job.status {
        case .running:
            runnerHost.runner.pause(job.id, reason: "manual")
        case .paused:
            runnerHost.runner.resume(job.id)
        case .completed:
            reReviewParent = job
        case .failed, .cancelled:
            let oldId = job.id
            let fresh = queue.enqueueReReview(of: job)
            queue.update(fresh.id) { j in j.parentJobId = nil }
            queue.remove(oldId)
            runnerHost.runner.start(fresh.id)
        case .queued:
            break
        }
    }

    private func runRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let outcomes = await refreshService.refreshAll()
        let merged = outcomes.filter(\.archivedNow).count
        let reReady = outcomes.filter(\.canReReview).count
        let dialogs = outcomes.reduce(0) { $0 + $1.learningDialogs }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        var parts: [String] = ["refresh \(f.string(from: Date()))", "\(outcomes.count) checked"]
        if merged > 0 { parts.append("\(merged) merged → removed") }
        if reReady > 0 { parts.append("\(reReady) ready for re-review") }
        if dialogs > 0 { parts.append("\(dialogs) replies → 🎓 ready") }
        refreshSummary = parts.joined(separator: " · ")
    }
}

/// Wraps the @MainActor runner so SwiftUI can hold it as a @StateObject.
@MainActor
final class RunnerHost: ObservableObject {
    let runner: ReviewRunner
    init(queue: ReviewQueueService) {
        self.runner = ReviewRunner(queue: queue)
    }
}

/// One row: verdict dot + title + counts + actions.
struct ReviewJobRow: View {
    let job: ReviewJob
    let onPrimary: () -> Void   // Start/Pause/Resume depending on status
    let onReveal: () -> Void
    let onRemove: () -> Void

    private var isActive: Bool {
        job.status == .running || job.status == .queued
    }
    private var isPaused: Bool { job.status == .paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Мини-строка над URL: Jira-ссылка · автор (EmptyView если данных нет)
            metaLine
                .padding(.leading, 22)
            if isPaused {
                pausedBanner
                    .padding(.leading, 22)
            }
            // По одной полной строке на каждый MR. Дата/длительность дублируются.
            ForEach(Array(job.mrs.enumerated()), id: \.element.id) { idx, mr in
                mrRow(mr: mr, isFirst: idx == 0)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var pausedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
            Text(pausedMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var pausedMessage: String {
        switch job.pauseReason {
        case "rate_limit":
            return "Ревью на паузе: лимиты Anthropic. Жми ▶ когда лимиты обновятся — продолжит с того же места."
        case "quota_exceeded", "usage_limit":
            return "Ревью на паузе: квота исчерпана. Жми ▶ когда восстановится."
        case "budget_exceeded":
            return "Ревью на паузе: превышен бюджет запроса. Жми ▶ чтобы продолжить."
        case "manual":
            return "Ревью на паузе. Жми ▶ чтобы продолжить."
        default:
            return "Ревью на паузе. Жми ▶ чтобы продолжить."
        }
    }

    /// One full row per MR: verdict | URL | date | duration | counts | (buttons only on the first row).
    /// Fixed-width columns → URL/date/duration/counts стоят в столбик у разных строк.
    @ViewBuilder
    private func mrRow(mr: ReviewMR, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            verdictDot(mr.verdict, animated: isActive)
                .frame(width: 12, alignment: .center)
            primaryLink(for: mr)
                .frame(maxWidth: 380, alignment: .leading)
            Text(startedAtFormatted)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 110, alignment: .leading)
            HStack(spacing: 2) {
                Image(systemName: "clock")
                Text(durationFormatted ?? "—")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
            .frame(width: 80, alignment: .leading)
            if isActive {
                statusLabel
                    .frame(width: 200, alignment: .leading)
            } else {
                Text(perMrCounts(mr))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 200, alignment: .leading)
            }
            Spacer(minLength: 8)
            if isFirst {
                rowButtons
            }
        }
    }

    @ViewBuilder
    private var rowButtons: some View {
        // Универсальная кнопка: pause (если running) / play (если paused / completed / failed).
        Button { onPrimary() } label: {
            Image(systemName: primaryIcon)
                .font(.callout.weight(primaryHighlighted ? .bold : .regular))
                .foregroundStyle(primaryColor)
                .padding(4)
                .background(
                    Circle().fill(primaryHighlighted ? primaryColor.opacity(0.12) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(primaryHelp)
        .disabled(job.status == .queued)

        Button { onReveal() } label: {
            Image(systemName: "folder")
        }
        .buttonStyle(.borderless)
        .help("Reveal log/result in Finder")

        if !isActive {
            Button { onRemove() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Remove from history")
        }
    }

    private var primaryIcon: String {
        switch job.status {
        case .running:   return "pause.circle.fill"
        case .paused:    return "play.circle.fill"
        case .completed: return "arrow.triangle.2.circlepath.circle.fill"
        case .failed, .cancelled: return "play.circle"
        case .queued:    return "hourglass"
        }
    }

    private var primaryColor: Color {
        switch job.status {
        case .running: return .orange
        case .paused: return .green
        case .completed, .failed, .cancelled:
            return job.canReReview ? .green : .purple
        case .queued: return .gray
        }
    }

    private var primaryHighlighted: Bool {
        job.status == .paused || (job.status == .completed && job.canReReview)
    }

    private var primaryHelp: String {
        switch job.status {
        case .running: return "Поставить на паузу. Сессия сохранится — можно продолжить позже."
        case .paused:
            return "Продолжить ревью с того же места (claude --resume)."
        case .completed:
            return job.canReReview
                ? "Re-review: автор ответил на все треды — классифицируй existing и допиши delta. [SUMMARY] перепишется."
                : "Re-review: классификатор existing-тредов + delta-only. [SUMMARY] перепишется."
        case .failed, .cancelled:
            return "Стартовать новое ревью этого MR (свежая сессия, без учёта прошлых тредов)."
        case .queued: return "Ждёт запуска…"
        }
    }

    private var countsLabel: String {
        // 💬 N — опубликованных комментов
        // 💬 N/M — N опубликовано, M получили ответ от автора (после refresh ↻)
        let comments: String = {
            let posted = job.totalComments
            let replied = job.totalThreadsReplied
            return replied > 0 ? "💬 \(posted)/\(replied)" : "💬 \(posted)"
        }()
        let parts: [String] = [
            "🔴 \(job.totalBlockers)",
            "🟠 \(job.totalMajor)",
            "🟡 \(job.totalMinor)",
            comments,
        ]
        return parts.joined(separator: " · ")
    }

    /// One MR row title: clickable URL if it parses, otherwise plain ref text.
    @ViewBuilder
    private func primaryLink(for mr: ReviewMR) -> some View {
        if let url = URL(string: mr.ref), let scheme = url.scheme, scheme.hasPrefix("http") {
            Link(destination: url) {
                Text(displayHost(url))
                    .font(.callout.weight(.medium))
                    .underline(true, pattern: .dot)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(mr.ref)
        } else {
            Text(mr.ref)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
    }

    /// Same as primaryLink but compact — used in per-MR sub-list of a multi-MR job.
    @ViewBuilder
    private func subLink(for mr: ReviewMR) -> some View {
        if let url = URL(string: mr.ref), let scheme = url.scheme, scheme.hasPrefix("http") {
            Link(destination: url) {
                Text(mr.title ?? displayHost(url))
                    .font(.caption2)
                    .underline(true, pattern: .dot)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(mr.ref)
        } else {
            Text(mr.title ?? mr.ref).font(.caption2).lineLimit(1)
        }
    }

    /// Per-MR counts: 🔴 N · 🟠 N · 🟡 N · 💬 наши_inline_threads/ответили.
    /// (commentsPosted обновляется refresh'ем: считаются только наши INLINE треды без summary)
    private func perMrCounts(_ mr: ReviewMR) -> String {
        var msg = "💬 \(mr.commentsPosted)"
        if mr.threadsRepliedByAuthor > 0 {
            msg += "/\(mr.threadsRepliedByAuthor)"
        }
        return "🔴 \(mr.blockers) · 🟠 \(mr.major) · 🟡 \(mr.minor) · \(msg)"
    }

    /// Shorten URL for display: drop scheme + `merge_requests/` → `!`, `/pull/` → `#`.
    private func displayHost(_ url: URL) -> String {
        var s = url.absoluteString
        s = s.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/-/merge_requests/", with: " !")
            .replacingOccurrences(of: "/merge_requests/", with: " !")
            .replacingOccurrences(of: "/pull/", with: " #")
        return s
    }

    /// Subtitle line: MR title if parsed, else CLS-key, else nothing.
    private var subtitleLine: String? {
        let mr = job.mrs.first
        if let t = mr?.title, !t.isEmpty { return t }
        if let cls = mr?.clsKey, !cls.isEmpty { return cls }
        return nil
    }

    /// Tiny meta row above the main URL line: Jira link + author username.
    @ViewBuilder
    private var metaLine: some View {
        let mr = job.mrs.first
        let cls = mr?.clsKey
        let author = mr?.author
        if cls != nil || author != nil {
            HStack(spacing: 6) {
                if let cls, let url = URL(string: "https://clussters.atlassian.net/browse/\(cls)") {
                    Link(destination: url) {
                        Text(cls)
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.blue)
                            .underline(true, pattern: .dot)
                    }
                    .help("Открыть тикет \(cls) в Jira")
                }
                if cls != nil && author != nil {
                    Text("·").foregroundStyle(.tertiary).font(.caption2)
                }
                if let author {
                    HStack(spacing: 2) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text("@\(author)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            EmptyView()
        }
    }

    private var startedAtFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: job.startedAt)
    }

    private var durationFormatted: String? {
        let end = job.finishedAt ?? (isActive ? Date() : job.startedAt)
        let seconds = Int(end.timeIntervalSince(job.startedAt))
        if seconds < 1 { return nil }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 3) {
            if job.status == .running {
                ProgressView().controlSize(.small).scaleEffect(0.55)
                Text("running…").font(.caption2).foregroundStyle(.secondary)
            } else if job.status == .queued {
                Text("queued…").font(.caption2).foregroundStyle(.secondary)
            } else if job.status == .paused {
                Image(systemName: "pause.fill").foregroundStyle(.orange)
                Text("paused").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func verdictDot(_ v: ReviewVerdict, animated: Bool, size: CGFloat = 12) -> some View {
        Circle()
            .fill(verdictColor(v))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
            .modifier(PulseIfActive(active: animated && v == .pending))
            .help(verdictHelp(v))
    }

    private func verdictColor(_ v: ReviewVerdict) -> Color {
        switch v {
        case .green: return .green
        case .yellow: return .orange      // «yellow» в enum = major, рисуем оранжевым
        case .red: return .red
        case .pending: return .gray
        case .failed: return .gray
        }
    }

    private func verdictHelp(_ v: ReviewVerdict) -> String {
        switch v {
        case .green: return "Можно мержить — только minor"
        case .yellow: return "Есть major-замечания"
        case .red: return "Мержить нельзя — есть blockers"
        case .pending: return "Ещё не закончилось"
        case .failed: return "Ошибка при ревью"
        }
    }
}

private struct PulseIfActive: ViewModifier {
    let active: Bool
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        if active {
            content
                .scaleEffect(scale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        scale = 1.25
                    }
                }
        } else {
            content
        }
    }
}
