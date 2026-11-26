import AppKit
import LimitsBarCore
import SwiftUI

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
                    Text(Lf("as of %@", s.fetchedAt.formatted(.dateTime.hour().minute())))
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
                    Text(L("No limits reported")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Checking…")).font(.caption).foregroundStyle(.secondary)
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
                Text(WindowLabel.display(window.label)).font(.caption)
                Spacer()
                Text(Lf("%d%% left", Int(window.remainingPercent.rounded())))
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
        date.timeIntervalSinceNow <= 0 ? L("resetting") : ResetFormat.short(date)
    }
}
