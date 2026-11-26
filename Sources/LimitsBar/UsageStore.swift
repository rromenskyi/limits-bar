import AppKit
import Foundation
import LimitsBarCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class UsageStore {
    static let pollInterval: TimeInterval = 5 * 60

    private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var config = Config()
    private(set) var configError: String?
    /// The file exists but doesn't parse; the last good config stays in use and nothing is saved.
    private var configLoadFailed = false

    private var pollTask: Task<Void, Never>?
    private var rateLimitStreak: [ProviderID: Int] = [:]
    private var refreshPending = false
    /// Called after every refresh with the fresh snapshots (alerts, open menu).
    var onRefresh: [@MainActor ([ProviderSnapshot]) -> Void] = []

    init(autoStart: Bool = true) {
        reloadConfig()
        if autoStart { start() }
    }

    // MARK: - Config

    /// Re-read on every refresh, so hand edits to config.json apply without a restart.
    func reloadConfig() {
        let (loaded, error) = Config.load()
        configError = error
        configLoadFailed = error != nil
        if error == nil { config = loaded }
        let known = Set(config.allProviderIDs)
        snapshots = snapshots.filter { known.contains($0.key) }
    }

    /// Applies a change on top of the file's current contents (so hand edits made since the last
    /// refresh survive) and saves. Refuses while the file has a syntax error, so a menu click can't
    /// replace a broken but recoverable config with defaults.
    private func mutateConfig(_ change: (inout Config) -> Void) {
        reloadConfig()
        guard !configLoadFailed else {
            configError = L("config.json has an error. Fix it before changing settings here.")
            return
        }
        change(&config)
        saveConfig()
    }

    private func saveConfig() {
        do { try config.save(); configError = nil } catch {
            configError = Lf("Could not save config.json: %@", error.localizedDescription)
        }
    }

    var allProviders: [ProviderID] { config.allProviderIDs }

    func isEnabled(_ id: ProviderID) -> Bool { config.isEnabled(id) }

    func setEnabled(_ id: ProviderID, _ on: Bool) {
        mutateConfig { c in
            var disabled = Set(c.disabled ?? [])
            if on { disabled.remove(id.id) } else { disabled.insert(id.id) }
            c.disabled = disabled.isEmpty ? nil : disabled.sorted()
        }
        if on { Task { await refresh() } }
    }

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: config.menuBar ?? "") ?? .compact }
        set { mutateConfig { $0.menuBar = newValue == .compact ? nil : newValue.rawValue } }
    }

    // MARK: Alerts

    var alertsEnabled: Bool {
        get { config.effectiveAlerts.isEnabled }
        set { updateAlerts { $0.enabled = newValue ? nil : false } }
    }

    func hasThreshold(_ t: Double) -> Bool { config.effectiveAlerts.effectiveThresholds.contains(t) }

    func toggleThreshold(_ t: Double) {
        updateAlerts { a in
            var set = Set(a.effectiveThresholds)
            if set.contains(t) { set.remove(t) } else { set.insert(t) }
            let sorted = set.sorted(by: >)
            a.thresholds = sorted == Config.Alerts.defaultThresholds ? nil : sorted
        }
    }

    var mutedAlerts: [String] { config.effectiveAlerts.muted ?? [] }

    func mute(_ key: String) {
        updateAlerts { a in
            var m = Set(a.muted ?? [])
            m.insert(key)
            a.muted = m.sorted()
        }
    }

    func unmuteAll() { updateAlerts { $0.muted = nil } }

    private func updateAlerts(_ change: (inout Config.Alerts) -> Void) {
        mutateConfig { c in
            var a = c.effectiveAlerts
            change(&a)
            c.alerts = a == Config.Alerts() ? nil : a
        }
    }

    func openConfigFile() {
        let url = Config.fileURL
        if !FileManager.default.fileExists(atPath: url.path) { saveConfig() }
        NSWorkspace.shared.open(url)
    }

    /// True when the provider's CLI or login wasn't found on this machine.
    func isMissing(_ id: ProviderID) -> Bool {
        if case .notConfigured = snapshots[id]?.status { return true }
        return false
    }

    /// Enabled providers that are actually present, in display order.
    var visible: [ProviderID] {
        allProviders.filter { isEnabled($0) && !isMissing($0) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("LimitsBar: launch at login change failed: \(error)")
            }
        }
    }

    // MARK: - Polling

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.pollInterval))
            }
        }
    }

    func refresh() async {
        // A refresh asked for while one runs (e.g. a provider was just enabled) runs right after it.
        guard !isRefreshing else { refreshPending = true; return }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshPending { refreshPending = false; Task { await refresh() } }
        }
        reloadConfig()
        let now = Date()
        let active = Providers.all(config: config).filter { p in
            // Respect a rate-limit backoff: keep the last snapshot instead of asking again.
            config.isEnabled(p.id) && !(snapshots[p.id]?.retryAfter.map { $0 > now } ?? false)
        }
        let results = await withTaskGroup(of: ProviderSnapshot.self) { group in
            for p in active { group.addTask { await p.fetch() } }
            var out: [ProviderSnapshot] = []
            for await s in group { out.append(s) }
            return out
        }
        for var s in results {
            if s.retryAfter != nil {
                let streak = (rateLimitStreak[s.provider] ?? 0) + 1
                rateLimitStreak[s.provider] = streak
                s.retryAfter = Date().addingTimeInterval(ProviderSnapshot.backoff(streak: streak))
            } else {
                rateLimitStreak[s.provider] = nil
            }
            snapshots[s.provider] = s.merged(over: snapshots[s.provider])
        }
        lastRefresh = Date()
        for handler in onRefresh { handler(results) }
        Snapshot.captureStatusItemIfRequested()
    }

    // MARK: - Menu bar

    var menuBarItems: [MenuBarIcon.Item] {
        visible.map { id in
            guard let s = snapshots[id] else {
                return MenuBarIcon.Item(tag: id.shortTag, short: nil, long: nil, dimmed: true)
            }
            let w = s.windows.map { $0.remainingPercent / 100 }
            return MenuBarIcon.Item(tag: id.shortTag, short: w.first,
                                    long: w.count > 1 ? w.dropFirst().min() : nil,
                                    dimmed: s.status != .ok)
        }
    }

    /// Text form, e.g. "C82 X12 M44 D100".
    var menuBarText: String {
        let items = visible.map { id in
            "\(id.shortTag)\(snapshots[id]?.minRemaining.map { String(Int($0.rounded())) } ?? "?")"
        }
        return items.isEmpty ? "–" : items.joined(separator: " ")
    }

    var accessibilityText: String {
        let parts = visible.map { id in
            "\(id.displayName) \(snapshots[id]?.minRemaining.map { Lf("%d%% left", Int($0.rounded())) } ?? "?")"
        }
        return parts.isEmpty ? "LimitsBar" : parts.joined(separator: ", ")
    }
}
