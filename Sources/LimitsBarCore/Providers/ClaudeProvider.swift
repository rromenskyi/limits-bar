import Foundation

/// Claude Code subscription limits.
///
/// Reads the OAuth token Claude Code stores in the login keychain (via `/usr/bin/security`, which
/// Claude Code itself uses, so no extra keychain prompt) and calls the same usage endpoint that
/// backs `/usage` in Claude Code. The token is never refreshed here: refreshing rotates the
/// refresh token and could sign Claude Code out. If it has expired, the row shows as stale until
/// Claude Code is used again.
public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude
    public init() {}

    static let keychainService = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            let creds = try await readCredentials()
            if let exp = creds.expiresAt, exp < Date() {
                throw ProviderError.stale(L("Token expired. Use Claude Code once to refresh it."))
            }
            var req = URLRequest(url: Self.usageURL)
            req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let json = try await HTTP.json(req, provider: "Claude")
            return ProviderSnapshot(provider: id, plan: creds.plan, windows: Self.parse(json))
        }
    }

    struct Credentials {
        var accessToken: String
        var expiresAt: Date?
        var plan: String?
    }

    func readCredentials() async throws -> Credentials {
        // Claude Code on Linux (and some setups) keeps the same JSON in a file.
        let file = (Env.value("CLAUDE_CONFIG_DIR").map { URL(fileURLWithPath: $0) }
                    ?? Env.home.appendingPathComponent(".claude"))
            .appendingPathComponent(".credentials.json")
        var data: Data?
        let security = URL(fileURLWithPath: "/usr/bin/security")
        if let r = try? await Shell.run(security, ["find-generic-password", "-s", Self.keychainService, "-w"], timeout: 15),
           r.status == 0, !r.stdout.isEmpty {
            data = r.stdout
        } else if let d = try? Data(contentsOf: file) {
            data = d
        }
        guard let data else {
            throw ProviderError.notConfigured(L("No Claude Code login found"))
        }
        return try Self.parseCredentials(data)
    }

    static func parseCredentials(_ data: Data) throws -> Credentials {
        let obj = try JSONObject.parse(data)
        guard let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ProviderError.notConfigured(L("Claude Code is not logged in with a subscription"))
        }
        let tier = (oauth["rateLimitTier"] as? String).flatMap(prettyTier)
        let sub = (oauth["subscriptionType"] as? String)?.capitalized
        let plan = [sub, tier].compactMap { $0 }.joined(separator: " · ")
        return Credentials(accessToken: token,
                           expiresAt: Dates.unixMillis(oauth["expiresAt"]),
                           plan: plan.isEmpty ? nil : plan)
    }

    /// "default_claude_max_5x" -> "Max 5x"
    static func prettyTier(_ raw: String) -> String? {
        guard let r = raw.range(of: "max_") else { return nil }
        return "Max " + raw[r.upperBound...]
    }

    static func parse(_ json: [String: Any]) -> [UsageWindow] {
        // Newer responses carry a generic `limits` list; prefer it when present.
        if let limits = json["limits"] as? [[String: Any]], !limits.isEmpty {
            let windows = limits.compactMap { item -> UsageWindow? in
                guard let pct = Num.double(item["percent"]) else { return nil }
                let kind = item["kind"] as? String ?? ""
                let scope = ((item["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let label: String
                switch kind {
                case "session": label = "5h"
                case "weekly_all": label = "Week"
                case "weekly_scoped": label = scope.map { "Week · \($0)" } ?? "Week (scoped)"
                default: label = scope ?? kind.replacingOccurrences(of: "_", with: " ").capitalized
                }
                return .fromUsed(label: label, usedPercent: pct, resetsAt: Dates.iso(item["resets_at"]))
            }
            if !windows.isEmpty { return windows }
        }
        let known: [(String, String)] = [
            ("five_hour", "5h"), ("seven_day", "Week"),
            ("seven_day_opus", "Week · Opus"), ("seven_day_sonnet", "Week · Sonnet"),
        ]
        return known.compactMap { key, label in
            guard let w = json[key] as? [String: Any], let used = Num.double(w["utilization"]) else { return nil }
            return .fromUsed(label: label, usedPercent: used, resetsAt: Dates.iso(w["resets_at"]))
        }
    }
}
