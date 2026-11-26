import AppKit
import LimitsBarCore
import Observation
import Sparkle
import SwiftUI

/// Owns the menu bar item. Following the macOS HIG for menu bar extras, a click (left or right)
/// opens a menu rather than a popover; the per-provider usage rows are custom menu item views.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let menuWidth: CGFloat = 300

    private let store: UsageStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let alerts: AlertNotifier
    private let updater: SPUStandardUpdaterController?
    private var menuIsOpen = false

    static let thresholdChoices: [Double] = [50, 30, 20, 10, 5]

    init(store: UsageStore, alerts: AlertNotifier, updater: SPUStandardUpdaterController?) {
        self.store = store
        self.alerts = alerts
        self.updater = updater
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        store.onRefresh.append { [weak self] _ in
            // Fresh numbers arrived while the menu is open: rebuild it in place.
            guard let self, self.menuIsOpen else { return }
            self.rebuild()
        }
        updateButton()
        Snapshot.captureMenuIfRequested(button: statusItem.button, menu: menu)
    }

    // MARK: - Button

    /// Redraws the button now and again whenever anything it reads from the store changes.
    private func updateButton() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateButton() }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        switch store.menuBarStyle {
        case .compact, .bars:
            button.title = ""
            button.image = store.menuBarStyle == .compact
                ? MenuBarIcon.compactImage(for: store.menuBarItems)
                : MenuBarIcon.image(for: store.menuBarItems)
            button.imagePosition = .imageOnly
        case .numbers:
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(string: store.menuBarText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular),
            ])
        }
        button.setAccessibilityLabel(store.accessibilityText)
        button.toolTip = store.accessibilityText
    }

    // MARK: - Menu

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild() }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated { menuIsOpen = false }
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuIsOpen = true
            Task { await alerts.updateStatus() }
            // Numbers older than two minutes get a background refresh; the rows update in place.
            if store.lastRefresh.map({ Date().timeIntervalSince($0) > 120 }) ?? true {
                Task { await store.refresh() }
            }
        }
    }

    private func rebuild() {
        menu.removeAllItems()

        if store.visible.isEmpty {
            menu.addItem(disabled(L(store.snapshots.isEmpty ? "Checking…" : "No supported CLIs found")))
        }
        for id in store.visible {
            menu.addItem(viewItem(ProviderMenuRow(store: store, id: id)))
        }
        if let err = store.configError {
            menu.addItem(disabled(err))
        }

        menu.addItem(.separator())
        menu.addItem(viewItem(UpdatedRow(store: store), highlight: false))
        menu.addItem(item(L("Refresh Now"), #selector(refreshNow), key: "r"))
        menu.addItem(.separator())

        let providers = NSMenuItem(title: L("Providers"), action: nil, keyEquivalent: "")
        let providersMenu = NSMenu()
        for id in store.allProviders {
            let mi = item(store.isMissing(id) ? Lf("%@ (not found)", id.displayName) : id.displayName,
                          #selector(toggleProvider(_:)))
            mi.representedObject = id.id
            mi.state = store.isEnabled(id) ? .on : .off
            providersMenu.addItem(mi)
        }
        providers.submenu = providersMenu
        menu.addItem(providers)

        let style = NSMenuItem(title: L("Menu Bar Style"), action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for s in MenuBarStyle.allCases {
            let mi = item(L(s.title), #selector(setStyle(_:)))
            mi.representedObject = s.rawValue
            mi.state = store.menuBarStyle == s ? .on : .off
            styleMenu.addItem(mi)
        }
        style.submenu = styleMenu
        menu.addItem(style)

        menu.addItem(alertsItem())

        let login = item(L("Launch at Login"), #selector(toggleLaunchAtLogin))
        login.state = store.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(item(L("Edit config.json…"), #selector(editConfig)))
        if let updater {
            let mi = NSMenuItem(title: L("Check for Updates…"),
                                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            mi.target = updater
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(item(L("Quit LimitsBar"), #selector(quit), key: "q"))
    }

    private func alertsItem() -> NSMenuItem {
        let root = NSMenuItem(title: L("Alerts"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        let enabled = item(L("Notify When Limits Run Low"), #selector(toggleAlerts))
        enabled.state = store.alertsEnabled ? .on : .off
        sub.addItem(enabled)
        if store.alertsEnabled && alerts.notificationsDenied {
            sub.addItem(item(L("Turn On Notifications in System Settings…"), #selector(openNotificationSettings)))
        }
        sub.addItem(.separator())
        for t in Self.thresholdChoices {
            let mi = item(Lf("At %d%% Left", Int(t)), #selector(toggleThreshold(_:)))
            mi.representedObject = t
            mi.state = store.hasThreshold(t) ? .on : .off
            mi.isEnabled = store.alertsEnabled
            sub.addItem(mi)
        }
        sub.addItem(.separator())
        let muted = store.mutedAlerts
        let unmute = item(muted.isEmpty ? L("No Muted Alerts") : Lf("Unmute All (%d)", muted.count), #selector(unmuteAll))
        unmute.isEnabled = !muted.isEmpty
        unmute.toolTip = muted.joined(separator: ", ")
        sub.addItem(unmute)
        sub.addItem(item(L("Send Test Alert"), #selector(testAlert)))
        root.submenu = sub
        return root
    }

    @objc private func toggleAlerts() {
        store.alertsEnabled.toggle()
        if store.alertsEnabled { alerts.requestPermission() }
    }

    @objc private func toggleThreshold(_ sender: NSMenuItem) {
        guard let t = sender.representedObject as? Double else { return }
        store.toggleThreshold(t)
    }

    @objc private func openNotificationSettings() { alerts.openNotificationSettings() }
    @objc private func unmuteAll() { store.unmuteAll() }
    @objc private func testAlert() { alerts.sendTest() }

    private func viewItem<V: View>(_ view: V, highlight: Bool = false) -> NSMenuItem {
        let host = NSHostingView(rootView: view
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(width: Self.menuWidth, alignment: .leading))
        host.frame.size = host.fittingSize
        let mi = NSMenuItem()
        mi.view = host
        return mi
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func refreshNow() { Task { await store.refresh() } }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = store.allProviders.first(where: { $0.id == raw }) else { return }
        store.setEnabled(id, !store.isEnabled(id))
    }

    @objc private func setStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = MenuBarStyle(rawValue: raw) else { return }
        store.menuBarStyle = s
    }

    @objc private func toggleLaunchAtLogin() { store.launchAtLogin.toggle() }
    @objc private func editConfig() { store.openConfigFile() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// One provider's usage inside the menu; reads the store so it updates while the menu is open.
struct ProviderMenuRow: View {
    let store: UsageStore
    let id: ProviderID

    var body: some View {
        ProviderCard(id: id, snapshot: store.snapshots[id])
            .padding(.vertical, 2)
    }
}

struct UpdatedRow: View {
    let store: UsageStore

    var body: some View {
        HStack(spacing: 6) {
            if store.isRefreshing {
                ProgressView().controlSize(.mini)
                Text(L("Refreshing…"))
            } else if let t = store.lastRefresh {
                Text(Lf("Updated %@", t.formatted(date: .omitted, time: .shortened)))
            } else {
                Text(L("Not updated yet"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?
    private var alerts: AlertNotifier?
    /// Sparkle runs only in a bundle that names a feed (release builds), never for `swift run`.
    private let updater: SPUStandardUpdaterController? =
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore(autoStart: false)
        let alerts = AlertNotifier(store: store)
        store.onRefresh.append { [weak alerts] snapshots in alerts?.process(snapshots) }
        self.alerts = alerts
        controller = StatusItemController(store: store, alerts: alerts, updater: updater)
        store.start()
    }
}
