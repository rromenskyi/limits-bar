import AppKit
import LimitsBarCore
import SwiftUI

struct LimitsBarApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(store: store)
        } label: {
            Text(store.menuBarText)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

struct UsagePanel: View {
    @Bindable var store: UsageStore
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.orderedEnabled.isEmpty {
                Text("No providers enabled.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.orderedEnabled, id: \.self) { id in
                ProviderCard(id: id, snapshot: store.snapshots[id])
            }
            Divider()
            if showSettings { settings; Divider() }
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Limits").font(.headline)
            Spacer()
            if let t = store.lastRefresh {
                Text(t, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .disabled(store.isRefreshing)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ProviderID.allCases, id: \.self) { id in
                Toggle(id.displayName, isOn: Binding(
                    get: { store.enabled.contains(id) },
                    set: { _ in store.toggle(id) }))
            }
            Divider()
            Toggle("Menu bar: tightest only", isOn: $store.compactLabel)
            Toggle("Launch at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.launchAtLogin = $0 }))
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack {
            Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

struct ProviderCard: View {
    let id: ProviderID
    let snapshot: ProviderSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(id.displayName).font(.subheadline.weight(.semibold))
                if let plan = snapshot?.plan {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let s = snapshot, s.status != .ok, !s.windows.isEmpty {
                    Text("as of \(s.fetchedAt.formatted(.dateTime.hour().minute()))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let s = snapshot {
                ForEach(Array(s.windows.enumerated()), id: \.offset) { _, w in
                    WindowRow(window: w)
                }
                if let msg = s.status.message {
                    Label(msg, systemImage: icon(for: s.status))
                        .font(.caption)
                        .foregroundStyle(color(for: s.status))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if s.windows.isEmpty, s.status == .ok {
                    Text("No limits reported").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func icon(for status: ProviderStatus) -> String {
        switch status {
        case .ok: "checkmark"
        case .stale: "clock.arrow.circlepath"
        case .notConfigured: "minus.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private func color(for status: ProviderStatus) -> Color {
        switch status {
        case .error: .orange
        default: .secondary
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label).font(.caption)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% left")
                    .font(.caption.monospacedDigit().weight(.medium))
                if let r = window.resetsAt {
                    Text("· \(resetText(r))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * window.remainingPercent / 100)
                }
            }
            .frame(height: 5)
        }
    }

    private var tint: Color {
        switch window.remainingPercent {
        case ..<10: .red
        case ..<30: .orange
        default: .green
        }
    }

    private func resetText(_ date: Date) -> String {
        let s = Int(date.timeIntervalSinceNow)
        if s <= 0 { return "resetting" }
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
