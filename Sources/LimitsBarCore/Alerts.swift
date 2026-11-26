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
/// Each (provider, window, threshold) fires once when remaining drops to or below the threshold,
/// and re-arms when remaining climbs back above it, which happens naturally when the window resets.
public enum AlertPlanner {
    public static func muteKey(_ p: ProviderID, _ w: UsageWindow) -> String { "\(p.id)/\(w.label)" }

    static func firedKey(_ p: ProviderID, _ w: UsageWindow, _ t: Double) -> String {
        "\(p.id)/\(w.label)/\(Int(t))"
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
                    if w.remainingPercent <= t {
                        if !fired.contains(key) {
                            fired.insert(key)
                            lowestNew = t
                        }
                    } else {
                        fired.remove(key)
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
