import Foundation

enum ScheduleStoreError: LocalizedError {
    case invalidName
    case alreadyExists(String)
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Schedule name: only a-z, 0-9, hyphen."
        case .alreadyExists(let n): return "Schedule '\(n)' already exists."
        case .readFailed(let m): return "Read failed: \(m)"
        case .writeFailed(let m): return "Write failed: \(m)"
        }
    }
}

enum ScheduleStore {
    static func directory() -> URL {
        AgentLoader.agentsDirectory().appendingPathComponent("schedules")
    }

    static func validate(name: String) -> Bool {
        name.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil
    }

    static func loadAll() -> [Schedule] {
        let dir = directory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var schedules: [Schedule] = []
        for url in entries where url.pathExtension == "json" && !url.lastPathComponent.contains(".runs.") {
            if let data = try? Data(contentsOf: url),
               let s = try? decoder.decode(Schedule.self, from: data) {
                schedules.append(s)
            }
        }
        return schedules.sorted { $0.name < $1.name }
    }

    static func save(_ schedule: Schedule, overwrite: Bool = false) throws {
        guard validate(name: schedule.name) else { throw ScheduleStoreError.invalidName }
        let dir = directory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(schedule.name).json")
        if !overwrite && FileManager.default.fileExists(atPath: url.path) {
            throw ScheduleStoreError.alreadyExists(schedule.name)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(schedule)
            try data.write(to: url)
        } catch {
            throw ScheduleStoreError.writeFailed(error.localizedDescription)
        }
    }

    static func delete(_ schedule: Schedule) {
        let dir = directory()
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(schedule.name).json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(schedule.name).runs.jsonl"))
    }

    // MARK: - Run history

    static func runsFile(for name: String) -> URL {
        directory().appendingPathComponent("\(name).runs.jsonl")
    }

    static func appendRun(_ run: ScheduleRun, scheduleName: String) {
        let url = runsFile(for: scheduleName)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(run) else { return }
        let line = (String(data: data, encoding: .utf8) ?? "") + "\n"
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8) ?? Data())
                try? handle.close()
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func loadRuns(for name: String, limit: Int = 50) -> [ScheduleRun] {
        let url = runsFile(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let stream = StreamReader(url: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var runs: [ScheduleRun] = []
        while let line = stream.nextLine() {
            guard let data = line.data(using: .utf8),
                  let run = try? decoder.decode(ScheduleRun.self, from: data) else { continue }
            runs.append(run)
        }
        return runs.suffix(limit).reversed()
    }
}
