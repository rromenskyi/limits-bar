import Foundation

/// Devin CLI daily and weekly quota.
///
/// Reads the API key the Devin CLI stores in `~/.local/share/devin/credentials.toml` and asks the
/// server listed there for the user status, the same call the CLI makes. Unlike the others, this
/// source reports *remaining* percent directly.
public struct DevinProvider: UsageProvider {
    public let id = ProviderID.devin
    public init() {}

    static var credentialsURL: URL {
        (Env.value("XDG_DATA_HOME").map { URL(fileURLWithPath: $0) }
            ?? Env.home.appendingPathComponent(".local/share"))
            .appendingPathComponent("devin/credentials.toml")
    }

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            guard let text = try? String(contentsOf: Self.credentialsURL, encoding: .utf8) else {
                throw ProviderError.notConfigured("No Devin CLI login found")
            }
            let creds = Self.parseTOML(text)
            guard let key = creds["windsurf_api_key"], !key.isEmpty else {
                throw ProviderError.notConfigured("Devin CLI is not logged in")
            }
            let server = creds["api_server_url"] ?? "https://server.codeium.com"
            guard let url = URL(string: server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                + "/exa.seat_management_pb.SeatManagementService/GetUserStatus") else {
                throw ProviderError.failed("Bad Devin server URL")
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            let body: [String: Any] = ["metadata": [
                "apiKey": key, "ideName": "limits-bar", "ideVersion": "1.0.0",
                "extensionName": "limits-bar", "extensionVersion": "1.0.0", "locale": "en",
            ]]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await HTTP.json(req, provider: "Devin")
            return Self.parse(json)
        }
    }

    /// Minimal `key = "value"` reader; the credentials file is flat.
    static func parseTOML(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces)
            var v = parts[1].trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            out[k] = v
        }
        return out
    }

    static func parse(_ json: [String: Any]) -> ProviderSnapshot {
        let status = json["userStatus"] as? [String: Any] ?? [:]
        let plan = status["planStatus"] as? [String: Any] ?? [:]
        var windows: [UsageWindow] = []
        if let day = Num.double(plan["dailyQuotaRemainingPercent"]) {
            windows.append(UsageWindow(label: "Day", remainingPercent: day,
                                       resetsAt: Dates.unixSeconds(plan["dailyQuotaResetAtUnix"])))
        }
        if let week = Num.double(plan["weeklyQuotaRemainingPercent"]) {
            windows.append(UsageWindow(label: "Week", remainingPercent: week,
                                       resetsAt: Dates.unixSeconds(plan["weeklyQuotaResetAtUnix"])))
        }
        let name = (plan["planInfo"] as? [String: Any])?["planName"] as? String
        return ProviderSnapshot(provider: .devin, plan: name, windows: windows)
    }
}
