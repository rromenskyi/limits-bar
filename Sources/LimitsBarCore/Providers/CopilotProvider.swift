import Foundation

/// GitHub Copilot monthly quotas (chat, completions, premium requests).
///
/// Uses the GitHub token of a Copilot editor plugin (`~/.config/github-copilot/apps.json` or
/// `hosts.json`) or, failing that, of the GitHub CLI (`gh auth token`), and reads the quota snapshot
/// that Copilot clients show. Read-only: the token is never refreshed or stored.
public struct CopilotProvider: UsageProvider {
    public let id = ProviderID.copilot
    public init() {}

    static let userURL = URL(string: "https://api.github.com/copilot_internal/user")!

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            guard let token = await Self.token() else {
                throw ProviderError.notConfigured(L("No GitHub login found (Copilot plugin or gh CLI)"))
            }
            var req = URLRequest(url: Self.userURL)
            req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let json = try await HTTP.json(req, provider: "GitHub",
                                           staleHint: L("Sign in to GitHub again (gh auth login)."),
                                           notFound: L("No Copilot plan on this GitHub account"))
            return try Self.parse(json)
        }
    }

    static func token() async -> String? {
        let dir = (Env.value("XDG_CONFIG_HOME").map { URL(fileURLWithPath: $0) }
            ?? Env.home.appendingPathComponent(".config")).appendingPathComponent("github-copilot")
        for file in ["apps.json", "hosts.json"] {
            if let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
               let t = pluginToken(data) { return t }
        }
        guard let gh = Env.which("gh"),
              let r = try? await Shell.run(gh, ["auth", "token", "--hostname", "github.com"], timeout: 10),
              r.status == 0 else { return nil }
        let t = String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.contains(where: \.isWhitespace) ? nil : t
    }

    /// `{"github.com:Iv1.b507a08c87ecfe98": {"user": "...", "oauth_token": "gho_..."}}`; only
    /// github.com entries count (a GitHub Enterprise token would be sent to the wrong host).
    static func pluginToken(_ data: Data) -> String? {
        guard let obj = try? JSONObject.parse(data) else { return nil }
        for key in obj.keys.sorted() where key == "github.com" || key.hasPrefix("github.com:") {
            if let entry = obj[key] as? [String: Any], let t = entry["oauth_token"] as? String, !t.isEmpty {
                return t
            }
        }
        return nil
    }

    static func parse(_ json: [String: Any]) throws -> ProviderSnapshot {
        guard let quotas = json["quota_snapshots"] as? [String: Any] else {
            // Accounts with Copilot through an organization may not report quotas at all.
            if json["copilot_plan"] != nil || json["access_type_sku"] != nil {
                return ProviderSnapshot(provider: .copilot, plan: plan(json), windows: [])
            }
            throw ProviderError.failed(L("Unexpected response format"))
        }
        let resets = Dates.iso(json["quota_reset_date_utc"])
        var windows: [UsageWindow] = []
        for (key, label) in [("premium_interactions", "Premium"), ("chat", "Chat"), ("completions", "Completions")] {
            guard let q = quotas[key] as? [String: Any],
                  (q["unlimited"] as? Bool) != true,
                  let entitlement = Num.double(q["entitlement"]), entitlement > 0,
                  let remaining = Num.double(q["percent_remaining"]) else { continue }
            windows.append(UsageWindow(label: label, remainingPercent: remaining, resetsAt: resets))
        }
        return ProviderSnapshot(provider: .copilot, plan: plan(json), windows: windows)
    }

    static func plan(_ json: [String: Any]) -> String? {
        let sku = (json["access_type_sku"] as? String ?? "").lowercased()
        if sku.contains("free") { return "Free" }
        if sku.contains("pro_plus") || sku.contains("pro+") { return "Pro+" }
        if sku.contains("pro") { return "Pro" }
        return (json["copilot_plan"] as? String)?.capitalized
    }
}
