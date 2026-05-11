import Foundation
import SwiftUI
import AppKit

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published var registeredProjects: [ClaudeProject] = []
    @Published var currentProject: ClaudeProject = .global
    @Published var showAddProjectSheet: Bool = false
    @Published var showPluginsBrowserSheet: Bool = false
    @Published var expandedProjectId: String?
    @Published var expandedSubsection: [String: Bool] = [
        "agents": true, "workflows": true, "schedules": true
    ]
    @Published var renamingProject: ClaudeProject?

    private let projectRepository: ProjectRepository
    private let onSwitch: () -> Void

    init(repository: ProjectRepository, onSwitch: @escaping () -> Void = {}) {
        self.projectRepository = repository
        self.onSwitch = onSwitch
        self.registeredProjects = repository.loadAll()
        self.currentProject = .global
        self.expandedProjectId = currentProject.id
        AgentPaths.current = currentProject.agentPaths
    }

    var allProjects: [ClaudeProject] { [.global] + registeredProjects }

    func switchProject(_ project: ClaudeProject) {
        currentProject = project
        expandedProjectId = project.id
        AgentPaths.current = project.agentPaths
        onSwitch()
    }

    func addProject(name: String, path: URL) {
        let project = ClaudeProject(name: name, path: path.path, isGlobal: false)
        projectRepository.add(project)
        let dir = project.agentPaths.agentsRoot
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: project.agentPaths.memoryDir, withIntermediateDirectories: true
        )
        installSessionStartHook(for: project)
        let sharedURL = dir.appendingPathComponent("SHARED.md")
        if !FileManager.default.fileExists(atPath: sharedURL.path) {
            try? "# Shared agent memory — \(name)\n\n".write(
                to: sharedURL, atomically: true, encoding: .utf8
            )
        }
        registeredProjects = projectRepository.loadAll()
        switchProject(project)
        AgentPaths.current = project.agentPaths
        _ = try? OrchestratorBuilder.build(agents: [], workflows: [])
        onSwitch()
    }

    func removeProject(_ project: ClaudeProject) {
        guard !project.isGlobal else { return }
        projectRepository.remove(project)
        registeredProjects = projectRepository.loadAll()
        if currentProject.id == project.id {
            switchProject(.global)
        }
    }

    func renameProject(_ project: ClaudeProject, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        projectRepository.rename(project, to: trimmed)
        registeredProjects = projectRepository.loadAll()
        if currentProject.id == project.id {
            currentProject = ClaudeProject(name: trimmed, path: project.path, isGlobal: project.isGlobal)
        }
    }

    private func installSessionStartHook(for project: ClaudeProject) {
        let settingsURL = project.url
            .appendingPathComponent(".claude/settings.local.json")
        try? FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = dict
        }

        let cmd = "if [ -f \"$PWD/.claude/agents/SHARED.md\" ]; then echo '=== Project shared agent memory (\(project.name)) ==='; cat \"$PWD/.claude/agents/SHARED.md\"; fi"
        let hookEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": cmd]]
        ]
        var hooks = (existing["hooks"] as? [String: Any]) ?? [:]
        var sessionStart = (hooks["SessionStart"] as? [[String: Any]]) ?? []
        sessionStart.removeAll { entry in
            if let inner = entry["hooks"] as? [[String: Any]] {
                return inner.contains { ($0["command"] as? String)?.contains("agents/SHARED.md") == true }
            }
            return false
        }
        sessionStart.append(hookEntry)
        hooks["SessionStart"] = sessionStart
        existing["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: existing,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }
}
