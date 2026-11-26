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
                throw ProviderError.notConfigured(L("No Devin CLI login found"))
            }
            let creds = Self.parseTOML(text)
            guard let key = creds["windsurf_api_key"], !key.isEmpty else {
                throw ProviderError.notConfigured(L("Devin CLI is not logged in"))
            }
            let server = creds["api_server_url"] ?? "https://server.codeium.com"
            guard let url = URL(string: server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                + "/exa.seat_management_pb.SeatManagementService/GetUserStatus"),
                  Self.isSafeServer(url) else {
                throw ProviderError.failed(L("Bad Devin server URL"))
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
            return try Self.parse(json)
        }
    }

    /// The API key is only ever sent over HTTPS, or plain HTTP to this Mac.
    static func isSafeServer(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        if url.scheme == "https" { return true }
        return url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    /// Reader for the flat `key = "value"` credentials file: handles double or single quotes and
    /// trailing `#` comments.
    static func parseTOML(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces)
            guard !k.hasPrefix("#"), !k.hasPrefix("[") else { continue }
            var v = Substring(parts[1].trimmingCharacters(in: .whitespaces))
            if let q = v.first, q == "\"" || q == "'", let end = v.dropFirst().firstIndex(of: q) {
                v = v[v.index(after: v.startIndex)..<end]
            } else if let hash = v.firstIndex(of: "#") {
                v = Substring(v[..<hash].trimmingCharacters(in: .whitespaces))
            }
            out[k] = String(v)
        }
        return out
    }

    static func parse(_ json: [String: Any]) throws -> ProviderSnapshot {
        guard let status = json["userStatus"] as? [String: Any],
              let plan = status["planStatus"] as? [String: Any] else {
            throw ProviderError.failed(L("Unexpected response format"))
        }
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
