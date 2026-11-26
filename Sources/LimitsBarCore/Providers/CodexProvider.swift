import Foundation

/// OpenAI Codex (ChatGPT sign-in) limits.
///
/// Reads `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) and calls the usage endpoint the Codex
/// CLI uses for `/status`. Read-only: tokens are never refreshed here.
public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex
    public init() {}

    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            let home = Env.value("CODEX_HOME").map { URL(fileURLWithPath: $0) }
                ?? Env.home.appendingPathComponent(".codex")
            guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")) else {
                throw ProviderError.notConfigured(L("No Codex login found"))
            }
            let auth = try JSONObject.parse(data)
            guard let tokens = auth["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String, !token.isEmpty else {
                throw ProviderError.notConfigured(L("Codex is not signed in with ChatGPT (API-key mode has no plan limits)"))
            }
            var req = URLRequest(url: Self.usageURL)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let account = tokens["account_id"] as? String {
                req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let json = try await HTTP.json(req, provider: "Codex")
            return Self.parse(json)
        }
    }

    static func parse(_ json: [String: Any]) -> ProviderSnapshot {
        let plan = (json["plan_type"] as? String)?.capitalized
        var windows: [UsageWindow] = []
        if let rl = json["rate_limit"] as? [String: Any] {
            for key in ["primary_window", "secondary_window"] {
                guard let w = rl[key] as? [String: Any], let used = Num.double(w["used_percent"]) else { continue }
                let label = Num.double(w["limit_window_seconds"]).map(windowLabel) ?? (key == "primary_window" ? "Short" : "Long")
                windows.append(.fromUsed(label: label, usedPercent: used, resetsAt: Dates.unixSeconds(w["reset_at"])))
            }
        }
        return ProviderSnapshot(provider: .codex, plan: plan, windows: windows)
    }

    /// 18000 -> "5h", 604800 -> "Week", 86400 -> "Day"
    static func windowLabel(_ seconds: Double) -> String {
        switch Int(seconds) {
        case 604_800: return "Week"
        case 86_400: return "Day"
        case let s where s % 3600 == 0: return "\(s / 3600)h"
        case let s: return "\(s / 60)m"
        }
    }
}
