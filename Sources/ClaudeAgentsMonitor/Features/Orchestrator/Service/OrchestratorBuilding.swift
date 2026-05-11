import Foundation

protocol OrchestratorBuilding {
    var agentName: String { get }
    func build(agents: [Agent], workflows: [Workflow]) throws -> URL
}

struct OrchestratorBuilderLive: OrchestratorBuilding {
    var agentName: String { OrchestratorBuilder.agentName }
    func build(agents: [Agent], workflows: [Workflow]) throws -> URL {
        try OrchestratorBuilder.build(agents: agents, workflows: workflows)
    }
}
