import Foundation
import Security

enum AgentVariablesError: LocalizedError {
    case invalidKey
    case keychainFailed(OSStatus)
    case fileFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Key должен быть в формате A-Z, 0-9, _ (например DB_PASSWORD)"
        case .keychainFailed(let s): return "Keychain error \(s)"
        case .fileFailed(let m): return "File error: \(m)"
        }
    }
}

enum AgentVariablesService {
    static func validate(key: String) -> Bool {
        key.range(of: "^[A-Z][A-Z0-9_]*$", options: .regularExpression) != nil
    }

    static func keychainService(for agentName: String) -> String {
        // Prefix with project id so the same agent name across projects doesn't collide.
        "claude-agent-\(AgentPaths.current.projectId)-\(agentName)"
    }

    static func varsFile(for agentName: String) -> URL {
        AgentLoader.agentsDirectory()
            .appendingPathComponent("memory/\(agentName).vars.json")
    }

    /// Returns all variables: plain ones with values, secrets with empty values + revealed=false.
    static func loadAll(for agentName: String) -> [AgentVariable] {
        var result: [AgentVariable] = []
        // Plain
        let plainURL = varsFile(for: agentName)
        if let data = try? Data(contentsOf: plainURL),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                result.append(AgentVariable(key: k, value: v, isSecret: false, revealed: true))
            }
        }
        // Secrets — list keys from Keychain
        let secretKeys = listKeychainKeys(service: keychainService(for: agentName))
        for k in secretKeys.sorted() {
            result.append(AgentVariable(key: k, value: "", isSecret: true, revealed: false))
        }
        return result
    }

    static func save(
        key: String,
        value: String,
        isSecret: Bool,
        for agentName: String
    ) throws {
        guard validate(key: key) else { throw AgentVariablesError.invalidKey }
        if isSecret {
            try saveKeychain(key: key, value: value, service: keychainService(for: agentName))
            // Remove from plain file if it existed there
            removeFromPlain(key: key, agentName: agentName)
        } else {
            try savePlain(key: key, value: value, agentName: agentName)
            // Remove from Keychain if it existed there
            try? removeKeychain(key: key, service: keychainService(for: agentName))
        }
    }

    static func delete(key: String, for agentName: String) {
        removeFromPlain(key: key, agentName: agentName)
        try? removeKeychain(key: key, service: keychainService(for: agentName))
    }

    static func revealSecret(key: String, for agentName: String) -> String? {
        readKeychain(key: key, service: keychainService(for: agentName))
    }

    // MARK: - Plain JSON

    private static func savePlain(key: String, value: String, agentName: String) throws {
        let url = varsFile(for: agentName)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var dict: [String: String] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            dict = existing
        }
        dict[key] = value
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
        } catch {
            throw AgentVariablesError.fileFailed(error.localizedDescription)
        }
    }

    private static func removeFromPlain(key: String, agentName: String) {
        let url = varsFile(for: agentName)
        guard let data = try? Data(contentsOf: url),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }
        dict.removeValue(forKey: key)
        if dict.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url)
            }
        }
    }

    // MARK: - Keychain

    private static func saveKeychain(key: String, value: String, service: String) throws {
        let data = value.data(using: .utf8) ?? Data()
        // Try update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return }

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AgentVariablesError.keychainFailed(addStatus)
        }
    }

    private static func readKeychain(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func removeKeychain(key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AgentVariablesError.keychainFailed(status)
        }
    }

    private static func listKeychainKeys(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
