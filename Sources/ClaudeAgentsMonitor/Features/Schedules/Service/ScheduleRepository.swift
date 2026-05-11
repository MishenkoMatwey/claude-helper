import Foundation

protocol ScheduleRepository {
    func loadAll() -> [Schedule]
    func save(_ schedule: Schedule, overwrite: Bool) throws
    func delete(_ schedule: Schedule)
    func appendRun(_ run: ScheduleRun, scheduleName: String)
    func loadRuns(for name: String, limit: Int) -> [ScheduleRun]
}

struct ScheduleRepositoryFile: ScheduleRepository {
    func loadAll() -> [Schedule] { ScheduleStore.loadAll() }
    func save(_ schedule: Schedule, overwrite: Bool) throws {
        try ScheduleStore.save(schedule, overwrite: overwrite)
    }
    func delete(_ schedule: Schedule) { ScheduleStore.delete(schedule) }
    func appendRun(_ run: ScheduleRun, scheduleName: String) {
        ScheduleStore.appendRun(run, scheduleName: scheduleName)
    }
    func loadRuns(for name: String, limit: Int) -> [ScheduleRun] {
        ScheduleStore.loadRuns(for: name, limit: limit)
    }
}
