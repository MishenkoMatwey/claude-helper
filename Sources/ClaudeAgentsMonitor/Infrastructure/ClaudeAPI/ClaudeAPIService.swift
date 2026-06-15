import Foundation
import Security

struct UsageBucket: Decodable, Hashable {
    let utilization: Double?
    let resets_at: String?

    var resetsAtDate: Date? {
        guard let s = resets_at else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

struct ExtraUsage: Decodable, Hashable {
    let is_enabled: Bool?
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?
    let currency: String?
}

struct OfficialUsage: Decodable, Hashable {
    let five_hour: UsageBucket?
    let seven_day: UsageBucket?
    let seven_day_oauth_apps: UsageBucket?
    let seven_day_opus: UsageBucket?
    let seven_day_sonnet: UsageBucket?
    let seven_day_cowork: UsageBucket?
    let seven_day_omelette: UsageBucket?
    let tangelo: UsageBucket?
    let iguana_necktie: UsageBucket?
    let omelette_promotional: UsageBucket?
    let extra_usage: ExtraUsage?
}

struct OfficialAccount: Decodable, Hashable {
    struct Account: Decodable, Hashable {
        let display_name: String?
        let email: String?
        let has_claude_max: Bool?
        let has_claude_pro: Bool?
    }
    struct Organization: Decodable, Hashable {
        let name: String?
        let organization_type: String?
        let rate_limit_tier: String?
    }
    let account: Account
    let organization: Organization
}

enum ClaudeAPIError: LocalizedError {
    case noToken
    case http(Int)
    case rateLimited(retryAt: Date)

    var errorDescription: String? {
        switch self {
        case .noToken: return "Claude Code OAuth token not found in Keychain"
        case .http(let code): return "HTTP \(code) from Claude API"
        case .rateLimited(let date):
            let s = Int(max(0, date.timeIntervalSinceNow))
            return "Rate limited by claude.com — retry in \(s)s"
        }
    }
}

actor ClaudeAPIService {
    static let shared = ClaudeAPIService()
    private let base = "https://api.anthropic.com"
    private var cachedToken: String?

    private var usageCache: (value: OfficialUsage, at: Date)?
    private var accountCache: (value: OfficialAccount, at: Date)?
    private var usageRetryAfter: Date?
    private let usageTTL: TimeInterval = 60
    private let accountTTL: TimeInterval = 600

    func usage() async throws -> OfficialUsage {
        if let c = usageCache, Date().timeIntervalSince(c.at) < usageTTL {
            return c.value
        }
        if let retryAt = usageRetryAfter, retryAt > Date() {
            throw ClaudeAPIError.rateLimited(retryAt: retryAt)
        }
        let value: OfficialUsage = try await get("/api/oauth/usage")
        usageCache = (value, Date())
        usageRetryAfter = nil
        return value
    }

    func account() async throws -> OfficialAccount {
        if let c = accountCache, Date().timeIntervalSince(c.at) < accountTTL {
            return c.value
        }
        let value: OfficialAccount = try await get("/api/oauth/profile")
        accountCache = (value, Date())
        return value
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let token = try fetchToken()
        var req = URLRequest(url: URL(string: base + path)!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-cli/2.1.126 (external, cli)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 401 { invalidateToken() }
            if http.statusCode == 429 {
                let secs = parseRetryAfter(http) ?? 60
                let retryAt = Date().addingTimeInterval(secs)
                if path.contains("usage") { usageRetryAfter = retryAt }
                throw ClaudeAPIError.rateLimited(retryAt: retryAt)
            }
            throw ClaudeAPIError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func parseRetryAfter(_ http: HTTPURLResponse) -> TimeInterval? {
        if let s = http.value(forHTTPHeaderField: "Retry-After"),
           let n = Double(s) { return n }
        if let s = http.value(forHTTPHeaderField: "anthropic-ratelimit-unified-reset"),
           let n = Double(s) { return max(0, n - Date().timeIntervalSince1970) }
        return nil
    }

    /// On-disk cache of the OAuth token so we don't read `Claude Code-credentials`
    /// from Keychain on every launch (each cold read pops a macOS keychain prompt).
    /// We only re-read Keychain when the cached token is missing or near expiry.
    private static let tokenCacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeAgentsMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-token.json")
    }()

    private func fetchToken() throws -> String {
        if let t = cachedToken { return t }
        // Disk cache — avoids a Keychain read (and its prompt) on cold start.
        if let cached = readDiskToken() {
            cachedToken = cached
            return cached
        }
        guard let kc = readKeychainToken() else { throw ClaudeAPIError.noToken }
        cachedToken = kc.token
        writeDiskToken(kc.token, expiresAtMillis: kc.expiresAt)
        return kc.token
    }

    /// Forget both caches (called on 401 — the token rotated, re-read source).
    private func invalidateToken() {
        cachedToken = nil
        try? FileManager.default.removeItem(at: Self.tokenCacheURL)
    }

    private func readDiskToken() -> String? {
        guard let data = try? Data(contentsOf: Self.tokenCacheURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String else { return nil }
        // Honour expiry with a 5-minute safety margin; treat missing expiry as valid.
        if let exp = obj["expiresAt"] as? Double {
            if Date().timeIntervalSince1970 * 1000 > exp - 5 * 60 * 1000 { return nil }
        }
        return token
    }

    private func writeDiskToken(_ token: String, expiresAtMillis: Double?) {
        var obj: [String: Any] = ["token": token]
        if let exp = expiresAtMillis { obj["expiresAt"] = exp }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        try? data.write(to: Self.tokenCacheURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: Self.tokenCacheURL.path)
    }

    private func readKeychainToken() -> (token: String, expiresAt: Double?)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let creds = (json["claudeAiOauth"] as? [String: Any]) ?? json
        guard let token = creds["accessToken"] as? String else { return nil }
        let expiresAt = (creds["expiresAt"] as? Double) ?? (creds["expiresAt"] as? Int).map(Double.init)
        return (token, expiresAt)
    }
}
