import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    static func notifyRateLimitPaused(workflow: String?, resumeAt: Date?) {
        var body = "Задача упёрлась в rate limit."
        if let when = resumeAt {
            let f = DateFormatter()
            f.timeStyle = .short
            body += " Auto-resume в \(f.string(from: when))."
        }
        let title = workflow.map { "⏸ Paused — \($0)" } ?? "⏸ Workflow paused"
        notify(title: title, body: body, identifier: "rate-limit-\(Date().timeIntervalSince1970)")
    }

    static func notifyScheduleFailed(name: String) {
        notify(
            title: "❌ Schedule failed",
            body: "\(name) не выполнилось — открой Dashboard для деталей.",
            identifier: "schedule-fail-\(name)-\(Date().timeIntervalSince1970)"
        )
    }

    static func notifyScheduleSucceeded(name: String) {
        notify(
            title: "✅ Schedule done",
            body: "\(name) отработало успешно.",
            identifier: "schedule-ok-\(name)-\(Date().timeIntervalSince1970)"
        )
    }
}
