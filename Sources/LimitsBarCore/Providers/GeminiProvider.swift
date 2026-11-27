import Foundation

/// Gemini CLI (Google sign-in) per-model daily quotas.
///
/// Reads the OAuth access token the Gemini CLI keeps in `~/.gemini/oauth_creds.json`, asks Code
/// Assist for the account's project (`loadCodeAssist`) and then for its quota buckets
/// (`retrieveUserQuota`), the calls the CLI makes for its model quota display. Read-only: an
/// expired token is reported as stale, never refreshed; the CLI refreshes it on its next run.
public struct GeminiProvider: UsageProvider {
    public let id = ProviderID.gemini
    public init() {}

    static let base = "https://cloudcode-pa.googleapis.com/v1internal"

    static var credentialsURL: URL {
        (Env.value("GEMINI_CLI_HOME").map { URL(fileURLWithPath: $0) } ?? Env.home)
            .appendingPathComponent(".gemini/oauth_creds.json")
    }

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            guard let data = try? Data(contentsOf: Self.credentialsURL) else {
                throw ProviderError.notConfigured(L("No Gemini CLI login found"))
            }
            let creds = try JSONObject.parse(data)
            guard let token = creds["access_token"] as? String, !token.isEmpty else {
                throw ProviderError.notConfigured(L("Gemini CLI is not signed in with Google"))
            }
            if let expiry = Dates.unixMillis(creds["expiry_date"]), expiry < Date() {
                throw ProviderError.stale(L("The Gemini CLI token has expired. Use the Gemini CLI once to refresh it."))
            }
            let load = try await Self.post("loadCodeAssist", token: token, body: [
                "metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"],
            ])
            guard let project = Self.project(load) else {
                throw ProviderError.notConfigured(L("This Google account has no Gemini Code Assist project"))
            }
            let quota = try await Self.post("retrieveUserQuota", token: token, body: ["project": project])
            return try Self.parse(quota, plan: Self.plan(load))
        }
    }

    static func post(_ method: String, token: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "\(base):\(method)")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await HTTP.json(req, provider: "Gemini")
    }

    /// `cloudaicompanionProject` is a string id here (an object only in onboarding responses).
    static func project(_ load: [String: Any]) -> String? {
        if let s = load["cloudaicompanionProject"] as? String, !s.isEmpty { return s }
        if let o = load["cloudaicompanionProject"] as? [String: Any], let s = o["id"] as? String, !s.isEmpty { return s }
        return nil
    }

    static func plan(_ load: [String: Any]) -> String? {
        if let paid = load["paidTier"] as? [String: Any], let name = paid["name"] as? String, !name.isEmpty { return name }
        switch (load["currentTier"] as? [String: Any])?["id"] as? String {
        case "free-tier": return "Free"
        case "standard-tier": return "Standard"
        case "legacy-tier": return "Legacy"
        default: return nil
        }
    }

    /// One window per model: `{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.8,
    /// "resetTime":"2026-11-27T08:00:00Z","tokenType":"REQUESTS"}]}`. A model listed twice keeps
    /// its tightest bucket.
    static func parse(_ json: [String: Any], plan: String?) throws -> ProviderSnapshot {
        guard let buckets = json["buckets"] as? [[String: Any]] else {
            throw ProviderError.failed(L("Unexpected response format"))
        }
        var order: [String] = []
        var best: [String: UsageWindow] = [:]
        for b in buckets {
            guard let fraction = Num.double(b["remainingFraction"]), fraction.isFinite else { continue }
            let label = modelLabel(b["modelId"] as? String)
            let w = UsageWindow(label: label, remainingPercent: fraction * 100, resetsAt: Dates.iso(b["resetTime"]))
            if let old = best[label] {
                if w.remainingPercent < old.remainingPercent { best[label] = w }
            } else {
                order.append(label)
                best[label] = w
            }
        }
        return ProviderSnapshot(provider: .gemini, plan: plan, windows: order.compactMap { best[$0] })
    }

    /// "gemini-2.5-flash-lite" -> "2.5 Flash Lite"; suffixes like "_vertex" are dropped.
    static func modelLabel(_ id: String?) -> String {
        guard var s = id?.split(separator: "_").first.map(String.init), !s.isEmpty else { return "Day" }
        if s.hasPrefix("gemini-") { s.removeFirst("gemini-".count) }
        return s.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
