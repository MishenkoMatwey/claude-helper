import Foundation
import SwiftUI

@MainActor
final class SchedulesViewModel: ObservableObject {
    @Published var showNewScheduleSheet: Bool = false
    @Published var editingSchedule: Schedule?
    @Published var pendingSelectionScheduleId: String?

    let scheduler: LocalScheduler

    init() {
        self.scheduler = LocalScheduler()
    }
}
