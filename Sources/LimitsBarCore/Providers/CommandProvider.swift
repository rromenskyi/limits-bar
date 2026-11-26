import Foundation

/// A provider defined in the config file: runs a command and reads usage JSON from its stdout.
///
/// Expected output (all fields but `windows` optional):
///
///     {
///       "plan": "Pro",
///       "windows": [
///         { "label": "Day",  "remainingPercent": 70, "resetsAt": "2030-01-01T00:00:00Z" },
///         { "label": "Week", "usedPercent": 40,      "resetsAt": 1893456000 }
///       ]
///     }
///
/// Print `{"error": "message"}` to show an error instead. `resetsAt` is an ISO 8601 string or
/// unix seconds.
public struct CommandProvider: UsageProvider {
    public let id: ProviderID
    let config: Config.CustomProvider

    public init(_ config: Config.CustomProvider) {
        self.config = config
        self.id = config.providerID
    }

    public func fetch() async -> ProviderSnapshot {
        await snapshot {
            guard let first = config.command.first, !first.isEmpty else {
                throw ProviderError.failed("No command set in config.json")
            }
            let expanded = (first as NSString).expandingTildeInPath
            let exe: URL
            if expanded.contains("/") {
                exe = URL(fileURLWithPath: expanded)
                guard FileManager.default.isExecutableFile(atPath: exe.path) else {
                    throw ProviderError.notConfigured("\(first) not found")
                }
            } else if let found = Env.which(expanded) {
                exe = found
            } else {
                throw ProviderError.notConfigured("\(first) not found")
            }
            let args = config.command.dropFirst().map { ($0 as NSString).expandingTildeInPath }
            let r = try await Shell.run(exe, Array(args), timeout: config.timeout ?? 60)
            guard let json = try? JSONObject.parse(r.stdout) else {
                let detail = r.stderr.split(separator: "\n").last.map(String.init) ?? "exit \(r.status)"
                throw ProviderError.failed("\(id.displayName) command printed no JSON: \(detail)")
            }
            return try Self.parse(json, id: id)
        }
    }

    static func parse(_ json: [String: Any], id: ProviderID) throws -> ProviderSnapshot {
        if let err = json["error"] as? String { throw ProviderError.failed(err) }
        let raw = json["windows"] as? [[String: Any]] ?? []
        let windows = raw.compactMap { w -> UsageWindow? in
            let label = w["label"] as? String ?? "Limit"
            let reset = Dates.iso(w["resetsAt"]) ?? Dates.unixSeconds(w["resetsAt"])
            if let rem = Num.double(w["remainingPercent"]) {
                return UsageWindow(label: label, remainingPercent: rem, resetsAt: reset)
            }
            if let used = Num.double(w["usedPercent"]) {
                return .fromUsed(label: label, usedPercent: used, resetsAt: reset)
            }
            return nil
        }
        return ProviderSnapshot(provider: id, plan: json["plan"] as? String, windows: windows)
    }
}
