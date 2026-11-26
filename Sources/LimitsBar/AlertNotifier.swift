import AppKit
import LimitsBarCore
import UserNotifications

/// Sends low-limit notifications with "Got It" and "Don't Remind Again" actions.
@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let category = "limit-low"
    nonisolated static let gotIt = "got-it"
    nonisolated static let mute = "mute"
    private static let firedKey = "alerts.fired"

    private let store: UsageStore
    private var center: UNUserNotificationCenter { .current() }

    init(store: UsageStore) {
        self.store = store
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [
                UNNotificationAction(identifier: Self.gotIt, title: L("Got It")),
                UNNotificationAction(identifier: Self.mute, title: L("Don't Remind Again"), options: [.destructive]),
            ], intentIdentifiers: []),
        ])
        if store.config.effectiveAlerts.isEnabled { requestPermission() }
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("LimitsBar: notification permission error: \(error.localizedDescription)") }
            else if !granted { NSLog("LimitsBar: notifications not allowed") }
        }
    }

    func process(_ snapshots: [ProviderSnapshot]) {
        let fired = Set(UserDefaults.standard.stringArray(forKey: Self.firedKey) ?? [])
        let plan = AlertPlanner.plan(snapshots: snapshots, alerts: store.config.effectiveAlerts, fired: fired)
        UserDefaults.standard.set(Array(plan.fired).sorted(), forKey: Self.firedKey)
        for alert in plan.alerts { send(alert) }
    }

    func send(_ alert: LimitAlert, test: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = Lf("%@ limit running low", alert.provider.displayName)
        var body = Lf("%@: %d%% left", WindowLabel.display(alert.window.label), Int(alert.window.remainingPercent.rounded()))
        if let r = alert.window.resetsAt { body = Lf("%@, resets in %@", body, ResetFormat.short(r)) }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["muteKey": alert.muteKey]
        let id = test ? "test-\(UUID().uuidString)" : alert.muteKey
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func sendTest() {
        requestPermission()
        let id = store.visible.first ?? .claude
        let window = store.snapshots[id]?.windows.min { $0.remainingPercent < $1.remainingPercent }
            ?? UsageWindow(label: "Week", remainingPercent: 12, resetsAt: Date().addingTimeInterval(86_400))
        send(LimitAlert(provider: id, window: window, threshold: 20), test: true)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let key = response.notification.request.content.userInfo["muteKey"] as? String
        guard response.actionIdentifier == Self.mute, let key else { return }
        await MainActor.run { store.mute(key) }
    }

    /// Show banners even though the menu bar app counts as active.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

enum ResetFormat {
    /// "2d 12h", "4h 32m", "7m", localized by the system.
    static func short(_ date: Date) -> String {
        let s = max(60, date.timeIntervalSinceNow)
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = s >= 86_400 ? [.day, .hour] : [.hour, .minute]
        return f.string(from: s) ?? ""
    }
}
