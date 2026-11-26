import Foundation

/// Muse Code allowance, via `muse usage --json`. The CLI handles its own sign-in and token refresh.
public struct MuseProvider: UsageProvider {
    public let id = ProviderID.muse
    public init() {}

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            guard let muse = Env.which("muse") else {
                throw ProviderError.notConfigured("muse CLI not found")
            }
            let r = try await Shell.run(muse, ["usage", "--json"], timeout: 90)
            guard let json = try? JSONObject.parse(r.stdout) else {
                let detail = r.stderr.split(separator: "\n").last.map(String.init) ?? "exit \(r.status)"
                if detail.localizedCaseInsensitiveContains("not logged in") {
                    throw ProviderError.notConfigured("Muse is not logged in")
                }
                throw ProviderError.failed("muse usage failed: \(detail)")
            }
            return try Self.parse(json)
        }
    }

    static func parse(_ json: [String: Any]) throws -> ProviderSnapshot {
        guard let allowance = json["allowance"] as? [String: Any] else {
            let reason = json["reason"] as? String ?? json["hint"] as? String ?? "no allowance data"
            throw ProviderError.failed("Muse: \(reason)")
        }
        var windows: [UsageWindow] = []
        for (key, label) in [("window", "Window"), ("weekly", "Week")] {
            guard let w = allowance[key] as? [String: Any], let used = Num.double(w["usedPercent"]) else { continue }
            windows.append(.fromUsed(label: label, usedPercent: used, resetsAt: Dates.unixMillis(w["resetsAtMs"])))
        }
        let tier = (allowance["tier"] as? String)?.replacingOccurrences(of: "Muse Code ", with: "")
        return ProviderSnapshot(provider: .muse, plan: tier, windows: windows)
    }
}
