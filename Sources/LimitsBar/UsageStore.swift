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

    private var pollTask: Task<Void, Never>?

    init(autoStart: Bool = true) {
        reloadConfig()
        if autoStart { start() }
    }

    // MARK: - Config

    /// Re-read on every refresh, so hand edits to config.json apply without a restart.
    func reloadConfig() {
        (config, configError) = Config.load()
        let known = Set(config.allProviderIDs)
        snapshots = snapshots.filter { known.contains($0.key) }
    }

    private func saveConfig() {
        do { try config.save(); configError = nil } catch {
            configError = "Could not save config.json: \(error.localizedDescription)"
        }
    }

    var allProviders: [ProviderID] { config.allProviderIDs }

    func isEnabled(_ id: ProviderID) -> Bool { config.isEnabled(id) }

    func setEnabled(_ id: ProviderID, _ on: Bool) {
        var disabled = Set(config.disabled ?? [])
        if on { disabled.remove(id.id) } else { disabled.insert(id.id) }
        config.disabled = disabled.isEmpty ? nil : disabled.sorted()
        saveConfig()
        if on { Task { await refresh() } }
    }

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: config.menuBar ?? "") ?? .bars }
        set { config.menuBar = newValue == .bars ? nil : newValue.rawValue; saveConfig() }
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        reloadConfig()
        let active = Providers.all(config: config).filter { config.isEnabled($0.id) }
        let results = await withTaskGroup(of: ProviderSnapshot.self) { group in
            for p in active { group.addTask { await p.fetch() } }
            var out: [ProviderSnapshot] = []
            for await s in group { out.append(s) }
            return out
        }
        for var s in results {
            // A failed check keeps the last known numbers, marked with the error, rather than blanking the row.
            if s.windows.isEmpty, let old = snapshots[s.provider], !old.windows.isEmpty,
               s.status != .ok, !Self.isMissingStatus(s.status) {
                s.windows = old.windows
                s.plan = s.plan ?? old.plan
                s.fetchedAt = old.fetchedAt
            }
            snapshots[s.provider] = s
        }
        lastRefresh = Date()
        NSLog("LimitsBar: refreshed: %@", menuBarText)
        Snapshot.captureStatusItemIfRequested()
    }

    private static func isMissingStatus(_ s: ProviderStatus) -> Bool {
        if case .notConfigured = s { return true }
        return false
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
            "\(id.displayName) \(snapshots[id]?.minRemaining.map { "\(Int($0.rounded())) percent left" } ?? "unknown")"
        }
        return parts.isEmpty ? "LimitsBar" : parts.joined(separator: ", ")
    }
}
