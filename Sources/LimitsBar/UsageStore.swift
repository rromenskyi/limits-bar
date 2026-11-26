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

    var enabled: Set<ProviderID> {
        didSet { UserDefaults.standard.set(enabled.map(\.rawValue), forKey: "enabledProviders") }
    }

    /// Show only the tightest provider in the menu bar instead of all of them.
    var compactLabel: Bool {
        didSet { UserDefaults.standard.set(compactLabel, forKey: "compactLabel") }
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

    private let providers: [any UsageProvider] = Providers.all()
    private var pollTask: Task<Void, Never>?

    init(autoStart: Bool = true) {
        let saved = UserDefaults.standard.stringArray(forKey: "enabledProviders")
        enabled = Set((saved ?? ProviderID.allCases.map(\.rawValue)).compactMap(ProviderID.init(rawValue:)))
        compactLabel = UserDefaults.standard.bool(forKey: "compactLabel")
        if autoStart { start() }
    }

    var orderedEnabled: [ProviderID] { ProviderID.allCases.filter(enabled.contains) }

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
        let active = providers.filter { enabled.contains($0.id) }
        let results = await withTaskGroup(of: ProviderSnapshot.self) { group in
            for p in active { group.addTask { await p.fetch() } }
            var out: [ProviderSnapshot] = []
            for await s in group { out.append(s) }
            return out
        }
        for var s in results {
            // A failed check keeps the last known numbers, marked with the error, rather than blanking the row.
            if s.windows.isEmpty, let old = snapshots[s.provider], !old.windows.isEmpty, s.status != .ok {
                s.windows = old.windows
                s.plan = s.plan ?? old.plan
                s.fetchedAt = old.fetchedAt
            }
            snapshots[s.provider] = s
        }
        lastRefresh = Date()
        NSLog("LimitsBar: refreshed: %@", menuBarText)
    }

    func toggle(_ id: ProviderID) {
        if enabled.contains(id) { enabled.remove(id) } else {
            enabled.insert(id)
            Task { await refresh() }
        }
    }

    /// Text for the menu bar item, e.g. "C82 X12 M44 D100".
    var menuBarText: String {
        let items = orderedEnabled.compactMap { id -> (ProviderID, Double?)? in
            guard let s = snapshots[id] else { return (id, nil) }
            if case .notConfigured = s.status { return nil }
            return (id, s.minRemaining)
        }
        if items.isEmpty { return snapshots.isEmpty ? "…" : "–" }
        if compactLabel, let tightest = items.filter({ $0.1 != nil }).min(by: { $0.1! < $1.1! }) {
            return "\(tightest.0.shortTag)\(Int(tightest.1!.rounded()))"
        }
        return items.map { id, v in "\(id.shortTag)\(v.map { String(Int($0.rounded())) } ?? "?")" }
            .joined(separator: " ")
    }
}
