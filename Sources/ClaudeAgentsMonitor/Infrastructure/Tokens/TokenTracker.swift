import Foundation

enum TokenTracker {
    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func loadSummary() -> TokenSummary {
        let projects = home.appendingPathComponent(".claude/projects")
        let sessionFiles = collectSessionFiles(under: projects)

        let now = Date()
        let fiveHourCutoff = now.addingTimeInterval(-5 * 3600)
        let weeklyCutoff = now.addingTimeInterval(-7 * 86400)
        let cutoffForScan = now.addingTimeInterval(-30 * 86400)

        var perDay: [String: (Int, Int, Int, Int, Int, Set<String>)] = [:]
        var perModel: [String: (Int, Int, Int, Int, Int)] = [:]
        var fiveH = (0, 0, 0, 0, 0, Date.distantFuture)
        var weekly = (0, 0, 0, 0, 0, Date.distantFuture)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        for file in sessionFiles {
            guard let stream = StreamReader(url: file) else { continue }
            while let line = stream.nextLine() {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let ts = obj["timestamp"] as? String,
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any]
                else { continue }
                let date = isoFormatter.date(from: ts) ?? fallbackFormatter.date(from: ts)
                guard let date else { continue }
                let day = String(ts.prefix(10))
                let input = (usage["input_tokens"] as? Int) ?? 0
                let output = (usage["output_tokens"] as? Int) ?? 0
                let cc = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                let cr = (usage["cache_read_input_tokens"] as? Int) ?? 0
                let model = (msg["model"] as? String) ?? "unknown"

                if date > cutoffForScan {
                    var d = perDay[day] ?? (0, 0, 0, 0, 0, [])
                    d.0 += input; d.1 += output; d.2 += cc; d.3 += cr; d.4 += 1
                    d.5.insert(file.lastPathComponent)
                    perDay[day] = d
                }
                if date > weeklyCutoff {
                    var m = perModel[model] ?? (0, 0, 0, 0, 0)
                    m.0 += input; m.1 += output; m.2 += cc; m.3 += cr; m.4 += 1
                    perModel[model] = m

                    weekly.0 += input; weekly.1 += output; weekly.2 += cc; weekly.3 += cr; weekly.4 += 1
                    if date < weekly.5 { weekly.5 = date }
                }
                if date > fiveHourCutoff {
                    fiveH.0 += input; fiveH.1 += output; fiveH.2 += cc; fiveH.3 += cr; fiveH.4 += 1
                    if date < fiveH.5 { fiveH.5 = date }
                }
            }
        }

        let stats = loadDailyActivity()
        let merged = perDay.map { day, v -> DailyTokens in
            let extra = stats.first(where: { $0.date == day })
            return DailyTokens(
                date: day, input: v.0, output: v.1, cacheCreate: v.2, cacheRead: v.3,
                messages: extra?.messages ?? v.4, sessions: extra?.sessions ?? v.5.count
            )
        }
        let sorted = merged.sorted { $0.date > $1.date }
        let todayStr = isoDate(now)

        let perModelArr = perModel
            .map { ModelUsage(model: $0.key, input: $0.value.0, output: $0.value.1,
                              cacheCreate: $0.value.2, cacheRead: $0.value.3, messages: $0.value.4) }
            .sorted { $0.total > $1.total }

        let fiveHourWindow = WindowUsage(
            label: "5h", duration: 5 * 3600,
            input: fiveH.0, output: fiveH.1, cacheCreate: fiveH.2, cacheRead: fiveH.3,
            messages: fiveH.4,
            oldestUsageAt: fiveH.5 == Date.distantFuture ? nil : fiveH.5
        )
        let weeklyWindow = WindowUsage(
            label: "7d", duration: 7 * 86400,
            input: weekly.0, output: weekly.1, cacheCreate: weekly.2, cacheRead: weekly.3,
            messages: weekly.4,
            oldestUsageAt: weekly.5 == Date.distantFuture ? nil : weekly.5
        )
        let activeSessions = recentActiveSessions(sessionFiles: sessionFiles)

        return TokenSummary(
            today: sorted.first(where: { $0.date == todayStr }),
            last7Days: Array(sorted.prefix(7)),
            last30Days: Array(sorted.prefix(30)),
            activeSessions: activeSessions,
            perModelLast7Days: perModelArr,
            fiveHourWindow: fiveHourWindow,
            weeklyWindow: weeklyWindow
        )
    }

    private static func collectSessionFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        return files
    }

    private static func recentActiveSessions(sessionFiles: [URL]) -> [ActiveSession] {
        let cutoff = Date().addingTimeInterval(-2 * 3600)
        let recent = sessionFiles.compactMap { url -> (URL, Date)? in
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = attrs.contentModificationDate,
                  modified > cutoff
            else { return nil }
            return (url, modified)
        }.sorted { $0.1 > $1.1 }

        return recent.prefix(20).compactMap { url, modified in
            sessionSummary(url: url, lastActivity: modified)
        }
    }

    private static func sessionSummary(url: URL, lastActivity: Date) -> ActiveSession? {
        guard let stream = StreamReader(url: url) else { return nil }
        var input = 0
        var output = 0
        var cacheRead = 0
        var startedAt: Date?
        var cwd = ""
        var model: String?
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        while let line = stream.nextLine() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if cwd.isEmpty, let c = obj["cwd"] as? String { cwd = c }
            if startedAt == nil, let ts = obj["timestamp"] as? String,
               let d = isoFormatter.date(from: ts) {
                startedAt = d
            }
            if let msg = obj["message"] as? [String: Any] {
                if model == nil, let m = msg["model"] as? String { model = m }
                if let usage = msg["usage"] as? [String: Any] {
                    input += (usage["input_tokens"] as? Int) ?? 0
                    output += (usage["output_tokens"] as? Int) ?? 0
                    cacheRead += (usage["cache_read_input_tokens"] as? Int) ?? 0
                }
            }
        }
        return ActiveSession(
            id: url.deletingPathExtension().lastPathComponent,
            cwd: cwd.isEmpty ? url.deletingLastPathComponent().lastPathComponent : cwd,
            startedAt: startedAt ?? lastActivity,
            lastActivity: lastActivity,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            model: model
        )
    }

    private static func loadDailyActivity() -> [DailyTokens] {
        let url = home.appendingPathComponent(".claude/stats-cache.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["dailyActivity"] as? [[String: Any]]
        else { return [] }
        return arr.compactMap {
            guard let date = $0["date"] as? String else { return nil }
            return DailyTokens(
                date: date, input: 0, output: 0, cacheCreate: 0, cacheRead: 0,
                messages: ($0["messageCount"] as? Int) ?? 0,
                sessions: ($0["sessionCount"] as? Int) ?? 0
            )
        }
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}

final class StreamReader {
    private let handle: FileHandle
    private var buffer = Data()
    private let chunkSize = 64 * 1024
    private let delimiter = Data([0x0A])

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.handle = handle
    }
    deinit { try? handle.close() }

    func nextLine() -> String? {
        while let range = buffer.range(of: delimiter) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            return String(data: lineData, encoding: .utf8) ?? ""
        }
        let chunk = handle.readData(ofLength: chunkSize)
        if chunk.isEmpty {
            if !buffer.isEmpty {
                let last = String(data: buffer, encoding: .utf8)
                buffer.removeAll()
                return last
            }
            return nil
        }
        buffer.append(chunk)
        return nextLine()
    }
}
