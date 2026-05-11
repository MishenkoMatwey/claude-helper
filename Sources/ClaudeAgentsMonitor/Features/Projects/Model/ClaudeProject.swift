import Foundation

struct ClaudeProject: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String     // display
    let path: String     // absolute path string
    let isGlobal: Bool

    var url: URL { URL(fileURLWithPath: path) }

    var agentPaths: AgentPaths {
        if isGlobal { return .global }
        return .project(name: name, root: url)
    }

    static let global = ClaudeProject(
        name: "User (global)",
        path: FileManager.default.homeDirectoryForCurrentUser.path,
        isGlobal: true
    )

    /// Cheap counts of project assets (one filesystem scan per call).
    /// Excludes auto-generated artifacts (SHARED.md, orchestrator.md).
    var counts: ProjectCounts {
        let paths = agentPaths
        let agents = (try? FileManager.default.contentsOfDirectory(at: paths.agentsRoot, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" }
            .filter { $0.lastPathComponent != "SHARED.md" }
            .filter { $0.lastPathComponent != "\(OrchestratorBuilder.agentName).md" }
            .count ?? 0
        let workflows = (try? FileManager.default.contentsOfDirectory(at: paths.workflowsDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" }
            .count ?? 0
        let schedules = (try? FileManager.default.contentsOfDirectory(at: paths.schedulesDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains(".runs.") }
            .count ?? 0
        return ProjectCounts(agents: agents, workflows: workflows, schedules: schedules)
    }
}

struct ProjectCounts {
    let agents: Int
    let workflows: Int
    let schedules: Int
    var total: Int { agents + workflows + schedules }
}
