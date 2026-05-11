import Foundation
import SwiftUI

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

func formatCountdown(to date: Date) -> String {
    let interval = date.timeIntervalSince(Date())
    if interval <= 0 { return "now" }
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    if h > 24 { return "\(h / 24)d \(h % 24)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

func formatResetTime(_ date: Date) -> String {
    let cal = Calendar.current
    let f = DateFormatter()
    if cal.isDateInToday(date) || cal.isDateInTomorrow(date) {
        f.dateFormat = "EEE h:mm a"
    } else {
        f.dateFormat = "EEE MMM d, h:mm a"
    }
    return f.string(from: date)
}

func progressColor(for percent: Double) -> Color {
    if percent >= 0.9 { return .red }
    if percent >= 0.7 { return .orange }
    if percent >= 0.5 { return .yellow }
    return .green
}
