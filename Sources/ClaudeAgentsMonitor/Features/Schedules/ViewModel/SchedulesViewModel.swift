import Foundation

/// The schedules editor UI was removed; what remains is the background
/// `LocalScheduler` that drives rate-limit-reset resumes for agent runs.
@MainActor
final class SchedulesViewModel: ObservableObject {
    let scheduler: LocalScheduler

    init() {
        self.scheduler = LocalScheduler()
    }
}
