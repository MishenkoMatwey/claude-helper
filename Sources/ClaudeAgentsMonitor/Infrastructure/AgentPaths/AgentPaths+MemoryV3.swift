import Foundation

/// v3 memory: a single SQLite database per project, living under `memoryDir`.
extension AgentPaths {
    var memoryDBFile: URL { memoryDir.appendingPathComponent("memory.db") }
}
