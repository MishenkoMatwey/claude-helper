import Foundation

/// Minimal 5-field cron parser. Supports `*`, integers, ranges (`1-5`),
/// comma lists (`1,15,30`) and step values (`*/15`, `0-30/5`).
/// Aliases: `@hourly`, `@daily`, `@weekly`.
struct CronExpression {
    let minutes: Set<Int>
    let hours: Set<Int>
    let days: Set<Int>
    let months: Set<Int>
    let weekdays: Set<Int>     // 0=Sunday … 6=Saturday

    init?(_ raw: String) {
        var expr = raw.trimmingCharacters(in: .whitespaces)
        switch expr {
        case "@hourly": expr = "0 * * * *"
        case "@daily", "@midnight": expr = "0 0 * * *"
        case "@weekly": expr = "0 0 * * 0"
        case "@monthly": expr = "0 0 1 * *"
        default: break
        }
        let parts = expr.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 5 else { return nil }
        guard let m = CronExpression.parse(parts[0], range: 0...59),
              let h = CronExpression.parse(parts[1], range: 0...23),
              let d = CronExpression.parse(parts[2], range: 1...31),
              let mo = CronExpression.parse(parts[3], range: 1...12),
              let w = CronExpression.parse(parts[4], range: 0...6)
        else { return nil }
        self.minutes = m
        self.hours = h
        self.days = d
        self.months = mo
        self.weekdays = w
    }

    private static func parse(_ field: String, range: ClosedRange<Int>) -> Set<Int>? {
        var values: Set<Int> = []
        for chunk in field.split(separator: ",") {
            let s = String(chunk)
            // step
            var basePart = s
            var step = 1
            if let slash = s.firstIndex(of: "/") {
                guard let st = Int(s[s.index(after: slash)...]) else { return nil }
                step = st
                basePart = String(s[..<slash])
            }
            // base: * | int | int-int
            if basePart == "*" {
                for v in stride(from: range.lowerBound, through: range.upperBound, by: step) {
                    values.insert(v)
                }
                continue
            }
            if let dash = basePart.firstIndex(of: "-"),
               let lo = Int(basePart[..<dash]),
               let hi = Int(basePart[basePart.index(after: dash)...]) {
                guard range.contains(lo), range.contains(hi) else { return nil }
                for v in stride(from: lo, through: hi, by: step) {
                    values.insert(v)
                }
                continue
            }
            guard let v = Int(basePart), range.contains(v) else { return nil }
            values.insert(v)
        }
        return values
    }

    /// Does the given moment match the schedule?
    func matches(_ date: Date) -> Bool {
        let cal = Calendar.current
        let comps = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let m = comps.minute, let h = comps.hour,
              let d = comps.day, let mo = comps.month, let w = comps.weekday else { return false }
        // Calendar.weekday: 1=Sunday … 7=Saturday → cron 0=Sunday … 6=Saturday
        let cronWeekday = (w - 1)
        return minutes.contains(m)
            && hours.contains(h)
            && days.contains(d)
            && months.contains(mo)
            && weekdays.contains(cronWeekday)
    }

    /// Compute the next fire time strictly after `from`. Returns nil if not found in 1 year.
    func nextDate(after from: Date) -> Date? {
        let cal = Calendar.current
        var current = cal.date(byAdding: .minute, value: 1, to: from) ?? from
        // Truncate to the start of the minute.
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: current)
        guard let truncated = cal.date(from: comps) else { return nil }
        current = truncated
        let limit = cal.date(byAdding: .year, value: 1, to: from) ?? from
        var iterations = 0
        while current <= limit, iterations < 60 * 24 * 366 {
            iterations += 1
            if matches(current) { return current }
            current = cal.date(byAdding: .minute, value: 1, to: current) ?? current
        }
        return nil
    }
}
