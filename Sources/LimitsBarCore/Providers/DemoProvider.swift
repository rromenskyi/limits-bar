import Foundation

/// Fixed sample data for screenshots and demos: `LIMITSBAR_DEMO=1`. No credentials are read and
/// no network requests are made.
public struct DemoProvider: UsageProvider {
    public let id: ProviderID
    let plan: String
    let windows: [(String, Double, TimeInterval)]

    public func fetch() async -> ProviderSnapshot {
        ProviderSnapshot(provider: id, plan: plan, windows: windows.map {
            UsageWindow(label: $0.0, remainingPercent: $0.1, resetsAt: Date().addingTimeInterval($0.2))
        })
    }

    public static var isEnabled: Bool { Env.value("LIMITSBAR_DEMO") != nil }

    public static func all() -> [any UsageProvider] {
        let h: TimeInterval = 3600, d: TimeInterval = 86_400
        return [
            DemoProvider(id: .claude, plan: "Max 5x", windows: [
                ("5h", 72, 2 * h + 14 * 60), ("Week", 58, 3 * d + 6 * h), ("Week · Opus", 81, 3 * d + 6 * h)]),
            DemoProvider(id: .codex, plan: "Plus", windows: [("5h", 64, 3 * h + 41 * 60), ("Week", 18, d + 19 * h)]),
            DemoProvider(id: .muse, plan: "Power Usage", windows: [("Window", 88, 4 * h + 2 * 60), ("Week", 44, 4 * d + 2 * h)]),
            DemoProvider(id: .devin, plan: "Pro", windows: [("Day", 100, 13 * h + 20 * 60), ("Week", 91, 2 * d + 13 * h)]),
        ]
    }
}
