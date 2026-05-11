import Foundation

struct AgentVariable: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let value: String      // empty for secrets unless explicitly revealed
    let isSecret: Bool
    let revealed: Bool     // true when value is loaded from Keychain
}
