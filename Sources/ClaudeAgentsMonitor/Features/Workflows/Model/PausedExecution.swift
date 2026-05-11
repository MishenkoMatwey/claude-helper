import Foundation

struct PausedExecution: Codable, Identifiable, Hashable {
    var id: String { sessionId }
    let sessionId: String
    let agentName: String           // orchestrator or single agent
    let workflowName: String?       // if started via Run workflow
    let originalPrompt: String
    let pausedAt: Date
    let reason: String              // "5h rate limit", "weekly limit"
    let resumeAfter: Date?          // when limit is expected to reset
    let resumeKind: ResumeKind
    var attempts: Int

    enum ResumeKind: String, Codable {
        case fiveHour, weekly
    }
}
