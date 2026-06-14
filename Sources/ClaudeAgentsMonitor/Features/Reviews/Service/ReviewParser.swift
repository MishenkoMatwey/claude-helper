import Foundation

/// Parses orchestrator's structured review output (text per MR) into findings counts.
///
/// Expected markers (used by orchestrator-clussters/playbooks.md `review-mr`):
///   "## MR <ref>" or "## MR <N>" or "## MR <url>"
///   "🔴 Blockers (N)"
///   "🟠 Major (N)"
///   "🟡 Minor (N)"
///   "comments posted: N" or "опубликовано N комментов"
///
/// If multiple MRs in one report — split by H2 starting with "## MR ".
enum ReviewParser {
    struct Findings {
        var blockers: Int = 0
        var major: Int = 0
        var minor: Int = 0
        var commentsPosted: Int = 0
        var clsKey: String?
        var title: String?
        var author: String?
    }

    /// Parse the full report, return findings keyed by MR ref/url heuristically.
    /// If we can't match individual sections — return one `Findings` under "*".
    static func parse(_ report: String) -> [String: Findings] {
        let sections = splitByMR(report)
        if sections.isEmpty {
            // No "## MR ..." headers — single-MR report, treat all as one.
            return ["*": parseSection(report)]
        }
        var out: [String: Findings] = [:]
        for (heading, body) in sections {
            let key = headingRefKey(heading)
            out[key] = parseSection(body, heading: heading)
        }
        return out
    }

    /// Apply parsed findings to a job's MR list. Matches by ref/url/CLS-key.
    static func apply(_ findings: [String: Findings], to job: inout ReviewJob) {
        for i in job.mrs.indices {
            let mr = job.mrs[i]
            let f = matchFindings(findings, for: mr)
            guard let f else { continue }
            job.mrs[i].blockers = f.blockers
            job.mrs[i].major = f.major
            job.mrs[i].minor = f.minor
            job.mrs[i].commentsPosted = f.commentsPosted
            if let cls = f.clsKey, job.mrs[i].clsKey == nil { job.mrs[i].clsKey = cls }
            if let t = f.title, job.mrs[i].title == nil { job.mrs[i].title = t }
            if let a = f.author, job.mrs[i].author == nil { job.mrs[i].author = a }
            job.mrs[i].verdict = ReviewVerdict.fromFindings(
                blockers: f.blockers, major: f.major, minor: f.minor
            )
        }
    }

    // MARK: - Internals

    private static func splitByMR(_ text: String) -> [(heading: String, body: String)] {
        let lines = text.components(separatedBy: "\n")
        var current: [String] = []
        var heading: String?
        var result: [(String, String)] = []
        for ln in lines {
            if ln.hasPrefix("## MR ") || ln.hasPrefix("# MR ") {
                if let h = heading {
                    result.append((h, current.joined(separator: "\n")))
                }
                heading = ln
                current = []
            } else {
                current.append(ln)
            }
        }
        if let h = heading {
            result.append((h, current.joined(separator: "\n")))
        }
        return result
    }

    private static func headingRefKey(_ heading: String) -> String {
        // "## MR 838 — title" → "838"; "## MR https://.../merge_requests/45 — ..." → URL
        let stripped = heading
            .replacingOccurrences(of: "## MR ", with: "")
            .replacingOccurrences(of: "# MR ", with: "")
        let dashIdx = stripped.firstIndex(where: { $0 == "—" || $0 == "-" || $0 == "·" })
        let ref = (dashIdx.map { stripped[..<$0] } ?? Substring(stripped))
            .trimmingCharacters(in: .whitespaces)
        return ref.isEmpty ? "*" : ref
    }

    /// Pull the title that sits *after* the em-dash/hyphen in "## MR <ref> — <title>".
    private static func headingTitle(_ heading: String) -> String? {
        let stripped = heading
            .replacingOccurrences(of: "## MR ", with: "")
            .replacingOccurrences(of: "# MR ", with: "")
        let separators: [Character] = ["—", "–", "·"]
        guard let idx = stripped.firstIndex(where: { separators.contains($0) }) else { return nil }
        let after = stripped[stripped.index(after: idx)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? nil : after
    }

    private static func parseSection(_ text: String, heading: String? = nil) -> Findings {
        var f = Findings()
        f.blockers = extractCount(text, markers: ["Blockers", "🔴 Blockers"])
        f.major = extractCount(text, markers: ["Major", "🟠 Major"])
        f.minor = extractCount(text, markers: ["Minor", "🟡 Minor"])
        f.commentsPosted = extractPostedCount(text)
        f.clsKey = extractFirstMatch(text, pattern: #"CLS-\d+"#)
        // Title — prefer the heading "## MR <ref> — <title>" line; fall back to body search.
        f.title = heading.flatMap(headingTitle) ?? extractTitle(text)
        // Author — может быть как "m.bogdanov", так и "Mikhail Bogdanov"; остановиться на ` ·` / `\n` / ` -` / `**`.
        f.author = extractFirstMatch(text, pattern: #"\*{0,2}Author\*{0,2}:\s*\*{0,2}([^\n·*]+?)\*{0,2}(?:\s+·|\s*\n|$)"#)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return f
    }

    /// Find `(N)` after one of the markers anywhere in the section.
    private static func extractCount(_ text: String, markers: [String]) -> Int {
        for marker in markers {
            let escaped = NSRegularExpression.escapedPattern(for: marker)
            let pattern = #"\#(escaped)[^\n]*?\((\d+)\)"#
            if let n = firstCaptureInt(text, pattern: pattern) { return n }
        }
        return 0
    }

    private static func extractPostedCount(_ text: String) -> Int {
        // "опубликовано 5 комментов" / "comments posted: 5" / "**comments posted:** 8" / "posted: 5 comments"
        // Markdown **bold** wrappers, em-dashes, multiple separators allowed before the digit.
        for pat in [
            #"опубликовано[*\s:]+(\d+)[*\s]+(?:коммент|comment)"#,
            #"\*{0,2}comments?\s+posted\*{0,2}[*\s:—–-]+(\d+)"#,
            #"posted[*\s:—–-]+(\d+)\s*(?:line-?)?comments?"#,
            #"(\d+)\s+(?:line-?)?comments?\s+posted"#,
        ] {
            if let n = firstCaptureInt(text, pattern: pat, options: [.caseInsensitive]) { return n }
        }
        return 0
    }

    private static func extractTitle(_ text: String) -> String? {
        // Try "Title: ..." or first line after "## MR" we already stripped.
        if let line = extractFirstMatch(text, pattern: #"(?:Title|title)[:\s]+([^\n]+)"#) {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func firstCaptureInt(
        _ text: String, pattern: String, options: NSRegularExpression.Options = []
    ) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    private static func extractFirstMatch(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              let r = Range(m.range(at: m.numberOfRanges - 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Best-effort: pick findings that look like this MR's.
    private static func matchFindings(_ findings: [String: Findings], for mr: ReviewMR) -> Findings? {
        // single-MR result
        if let single = findings["*"], findings.count == 1 { return single }
        // direct ref match
        if let f = findings[mr.ref] { return f }
        // url substring
        for (k, v) in findings {
            if k.contains(mr.ref) { return v }
            if let url = mr.resolvedUrl, k.contains(url) || url.contains(k) { return v }
        }
        // by CLS key
        if let cls = mr.clsKey {
            for (_, v) in findings where v.clsKey == cls { return v }
        }
        // fallback to first if exactly one section
        if findings.count == 1 { return findings.values.first }
        return nil
    }
}
