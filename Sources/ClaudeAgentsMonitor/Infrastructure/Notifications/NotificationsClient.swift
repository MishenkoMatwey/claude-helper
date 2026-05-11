import Foundation

protocol NotificationsClient {
    func requestAuthorization()
    func notify(title: String, body: String)
    func notifyRateLimitPaused(workflow: String?, resumeAt: Date?)
    func notifyScheduleFailed(name: String)
    func notifyScheduleSucceeded(name: String)
}

struct NotificationsClientLive: NotificationsClient {
    func requestAuthorization() { NotificationService.requestAuthorization() }
    func notify(title: String, body: String) {
        NotificationService.notify(title: title, body: body)
    }
    func notifyRateLimitPaused(workflow: String?, resumeAt: Date?) {
        NotificationService.notifyRateLimitPaused(workflow: workflow, resumeAt: resumeAt)
    }
    func notifyScheduleFailed(name: String) { NotificationService.notifyScheduleFailed(name: name) }
    func notifyScheduleSucceeded(name: String) { NotificationService.notifyScheduleSucceeded(name: name) }
}
