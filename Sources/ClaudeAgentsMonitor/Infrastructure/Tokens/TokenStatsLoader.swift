import Foundation

protocol TokenStatsLoader {
    func loadSummary() -> TokenSummary
}

struct TokenStatsLoaderFile: TokenStatsLoader {
    func loadSummary() -> TokenSummary { TokenTracker.loadSummary() }
}
