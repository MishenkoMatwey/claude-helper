import Foundation

protocol ClaudeAPIClient {
    func usage() async throws -> OfficialUsage
    func account() async throws -> OfficialAccount
}

struct ClaudeAPIClientLive: ClaudeAPIClient {
    func usage() async throws -> OfficialUsage { try await ClaudeAPIService.shared.usage() }
    func account() async throws -> OfficialAccount { try await ClaudeAPIService.shared.account() }
}
