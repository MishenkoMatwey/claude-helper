import Foundation
import SwiftUI

@MainActor
final class WorkflowsViewModel: ObservableObject {
    @Published var workflows: [Workflow] = []
    @Published var showNewWorkflowSheet: Bool = false
    @Published var editingWorkflow: Workflow?
    @Published var pendingSelectionWorkflowId: String?
    @Published var orchestratorBuildResult: String?

    private let workflowRepository: WorkflowRepository
    private let getAgents: () -> [Agent]

    init(workflowRepository: WorkflowRepository, getAgents: @escaping () -> [Agent]) {
        self.workflowRepository = workflowRepository
        self.getAgents = getAgents
    }

    func reload() {
        workflows = workflowRepository.loadAll()
    }

    func generateOrchestrator() {
        do {
            _ = try OrchestratorBuilder.build(agents: getAgents(), workflows: workflows)
            let count = getAgents().filter { $0.name != OrchestratorBuilder.agentName }.count
            orchestratorBuildResult = "Orchestrator updated — \(count) agents, \(workflows.count) workflows."
        } catch {
            orchestratorBuildResult = "Failed: \(error.localizedDescription)"
        }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { self.orchestratorBuildResult = nil }
        }
    }
}
