import Foundation

/// Reads filesystem state to report on the project's auto-refresh pipeline:
/// backups, last successful run (from `last-refresh:` markers in `*.context.md`),
/// and the registered LaunchAgent / CAM schedule that drives it.
struct AutoRefreshStatus {
    struct Backup: Identifiable {
        let id: String
        let path: URL
        let date: Date
        let fileCount: Int
    }

    let backups: [Backup]
    let lastRefreshByAgent: [String: Date]   // agent name → last managed-block refresh date
    let launchAgentLabel: String?            // ~/Library/LaunchAgents/<label>.plist (if found)
    let nextScheduledRun: String?            // human-readable cron summary

    var lastSuccessfulRefresh: Date? {
        lastRefreshByAgent.values.max()
    }

    var lastBackup: Backup? { backups.first }

    static func load(projectPath: URL) -> AutoRefreshStatus {
        let agentsDir = projectPath.appendingPathComponent(".claude/agents")
        let backups = loadBackups(at: agentsDir.appendingPathComponent("_backup"))
        let lastRefresh = loadLastRefreshDates(memoryDir: agentsDir.appendingPathComponent("memory"))
        let (label, summary) = loadLaunchAgent()
        return AutoRefreshStatus(
            backups: backups,
            lastRefreshByAgent: lastRefresh,
            launchAgentLabel: label,
            nextScheduledRun: summary
        )
    }

    // MARK: Backups
    private static func loadBackups(at dir: URL) -> [Backup] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [Backup] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let count = (try? fm.contentsOfDirectory(atPath: url.path).count) ?? 0
            out.append(Backup(id: url.lastPathComponent, path: url, date: date, fileCount: count))
        }
        return out.sorted { $0.date > $1.date }
    }

    // MARK: Last-refresh markers
    private static func loadLastRefreshDates(memoryDir: URL) -> [String: Date] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil)
        else { return [:] }
        let isoLike = DateFormatter()
        isoLike.dateFormat = "yyyy-MM-dd"
        isoLike.locale = Locale(identifier: "en_US_POSIX")
        var out: [String: Date] = [:]
        for url in files where url.lastPathComponent.hasSuffix(".context.md") {
            let agent = url.lastPathComponent
                .replacingOccurrences(of: ".context.md", with: "")
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // Match all `last-refresh: YYYY-MM-DD` occurrences, keep the latest.
            let pattern = #"last-refresh:\s*(\d{4}-\d{2}-\d{2})"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            var best: Date?
            for m in matches {
                let dateStr = ns.substring(with: m.range(at: 1))
                if let d = isoLike.date(from: dateStr), (best == nil || d > best!) {
                    best = d
                }
            }
            if let b = best { out[agent] = b }
        }
        return out
    }

    // MARK: LaunchAgent
    private static func loadLaunchAgent() -> (label: String?, summary: String?) {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.mishchenko.refresh-contexts.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return (nil, nil) }
        let label = plist["Label"] as? String
        var summary: String?
        if let cal = plist["StartCalendarInterval"] as? [String: Any] {
            let h = cal["Hour"] as? Int ?? 0
            let m = cal["Minute"] as? Int ?? 0
            summary = String(format: "daily at %02d:%02d", h, m)
        }
        return (label, summary)
    }
}
