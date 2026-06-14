import Foundation

/// Holds the project's workflows. The editor UI was removed; workflows now exist
/// only as data the orchestrator references (via OrchestratorBuilder) — so this
/// VM just loads them for counts and orchestrator rebuilds.
@MainActor
final class WorkflowsViewModel: ObservableObject {
    @Published var workflows: [Workflow] = []

    private let workflowRepository: WorkflowRepository

    init(workflowRepository: WorkflowRepository) {
        self.workflowRepository = workflowRepository
    }

    func reload() {
        workflows = workflowRepository.loadAll()
    }
}
