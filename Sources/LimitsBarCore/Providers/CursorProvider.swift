import Foundation

/// Cursor plan usage for the current billing cycle.
///
/// Reads the session token the Cursor app keeps in its state database and asks cursor.com for the
/// usage summary its dashboard shows. Read-only: the database is opened read-only and the token
/// is never refreshed; Cursor refreshes it while the app runs.
public struct CursorProvider: UsageProvider {
    public let id = ProviderID.cursor
    public init() {}

    static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    static var databaseURL: URL {
        Env.home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            let db = Self.databaseURL
            guard FileManager.default.fileExists(atPath: db.path) else {
                throw ProviderError.notConfigured(L("No Cursor login found"))
            }
            let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken';"
            let r = try await Shell.run(URL(fileURLWithPath: "/usr/bin/sqlite3"), ["-readonly", db.path, query], timeout: 10)
            let token = String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard r.status == 0, !token.isEmpty, let user = Self.userID(fromJWT: token) else {
                throw ProviderError.notConfigured(L("Cursor is not signed in"))
            }
            var req = URLRequest(url: Self.summaryURL)
            req.setValue("WorkosCursorSessionToken=\(user)%3A%3A\(token)", forHTTPHeaderField: "Cookie")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let json = try await HTTP.json(req, provider: "Cursor", staleHint: L("Open Cursor once to refresh it."))
            return try Self.parse(json)
        }
    }

    /// The cookie names the user: the part of the JWT `sub` after the last "|"
    /// (`"auth0|user_01ABC"` -> `"user_01ABC"`).
    static func userID(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let payload = try? JSONObject.parse(data),
              let sub = payload["sub"] as? String,
              let user = sub.split(separator: "|").last.map(String.init),
              !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return user
    }

    /// `{"billingCycleEnd":"2026-09-18T08:09:13.000Z","membershipType":"pro","isUnlimited":false,
    /// "individualUsage":{"plan":{"enabled":true,"used":1516,"limit":2000,"remaining":484},
    /// "onDemand":{"enabled":false,"used":0,"limit":null}}}`. The percent fields in the same
    /// response have disagreed with the dashboard, so used and limit are what count.
    static func parse(_ json: [String: Any]) throws -> ProviderSnapshot {
        guard let usage = json["individualUsage"] as? [String: Any] else {
            throw ProviderError.failed(L("Unexpected response format"))
        }
        let resets = Dates.iso(json["billingCycleEnd"])
        var windows: [UsageWindow] = []
        if (json["isUnlimited"] as? Bool) != true {
            for (key, label) in [("plan", "Month"), ("onDemand", "On-Demand")] {
                guard let b = usage[key] as? [String: Any], (b["enabled"] as? Bool) != false,
                      let limit = Num.double(b["limit"]), limit > 0 else { continue }
                let remaining = Num.double(b["remaining"]) ?? Num.double(b["used"]).map { limit - $0 }
                guard let remaining else { continue }
                windows.append(UsageWindow(label: label, remainingPercent: remaining / limit * 100, resetsAt: resets))
            }
        }
        return ProviderSnapshot(provider: .cursor, plan: plan(json["membershipType"] as? String), windows: windows)
    }

    static func plan(_ membership: String?) -> String? {
        switch membership?.lowercased() {
        case nil, "": nil
        case "pro_plus", "pro-plus": "Pro+"
        case let m?: m.prefix(1).uppercased() + m.dropFirst()
        }
    }
}
