import Foundation

/// A notification to show because a window dropped to or below a threshold.
public struct LimitAlert: Sendable, Equatable {
    public var provider: ProviderID
    public var window: UsageWindow
    public var threshold: Double

    public init(provider: ProviderID, window: UsageWindow, threshold: Double) {
        self.provider = provider
        self.window = window
        self.threshold = threshold
    }

    /// Key used to mute this window permanently, e.g. "codex/Week".
    public var muteKey: String { AlertPlanner.muteKey(provider, window) }
}

/// Decides which low-limit alerts to send. Pure, so it can be tested without notifications.
///
/// Each (provider, window, threshold) fires once per quota period when remaining drops to or below
/// the threshold. It re-arms when remaining climbs back above the threshold, or when the window's
/// reset time moves on (a new period), even if the app missed the moment of the reset.
public enum AlertPlanner {
    public static func muteKey(_ p: ProviderID, _ w: UsageWindow) -> String { "\(p.id)/\(w.label)" }

    static func firedPrefix(_ p: ProviderID, _ w: UsageWindow, _ t: Double) -> String {
        "\(p.id)/\(w.label)/\(String(format: "%g", t))@"
    }

    /// The period is the reset time in 10-minute buckets, so jitter in reported reset times
    /// doesn't look like a new period.
    static func firedKey(_ p: ProviderID, _ w: UsageWindow, _ t: Double) -> String {
        let period = w.resetsAt.map { String(Int(($0.timeIntervalSince1970 / 600).rounded())) } ?? "-"
        return firedPrefix(p, w, t) + period
    }

    /// - Returns: alerts to send now (at most one per window: the lowest threshold crossed) and the
    ///   updated set of fired keys to persist.
    public static func plan(snapshots: [ProviderSnapshot], alerts: Config.Alerts,
                            fired: Set<String>) -> (alerts: [LimitAlert], fired: Set<String>) {
        var fired = fired
        var out: [LimitAlert] = []
        let muted = Set(alerts.muted ?? [])
        let thresholds = alerts.effectiveThresholds
        for s in snapshots where s.status == .ok {
            for w in s.windows {
                var lowestNew: Double?
                for t in thresholds {
                    let key = firedKey(s.provider, w, t)
                    let prefix = firedPrefix(s.provider, w, t)
                    if w.remainingPercent <= t {
                        if !fired.contains(key) {
                            fired = fired.filter { !$0.hasPrefix(prefix) }  // drop older periods
                            fired.insert(key)
                            lowestNew = t
                        }
                    } else {
                        fired = fired.filter { !$0.hasPrefix(prefix) }
                    }
                }
                if alerts.isEnabled, let t = lowestNew, !muted.contains(muteKey(s.provider, w)) {
                    out.append(LimitAlert(provider: s.provider, window: w, threshold: t))
                }
            }
        }
        return (out, fired)
    }
}
