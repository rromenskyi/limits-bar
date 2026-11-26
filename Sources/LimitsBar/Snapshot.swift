import AppKit
import SwiftUI

/// Approximates the menu's usage rows for `--snapshot`.
struct MenuPreview: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.visible, id: \.self) { ProviderMenuRow(store: store, id: $0) }
            Divider()
            UpdatedRow(store: store)
        }
        .padding(14)
        .frame(width: StatusItemController.menuWidth)
        .background(.background)
    }
}

@MainActor
enum Snapshot {
    /// Writes the panel to `url` and the menu bar item (light and dark, 2x) next to it as `<name>-menubar.png`.
    static func write(to url: URL) async {
        _ = NSApplication.shared
        let store = UsageStore(autoStart: false)
        await store.refresh()

        let host = NSHostingView(rootView: MenuPreview(store: store))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }

        let icon = MenuBarIcon.compactImage(for: store.menuBarItems)
        let scale: CGFloat = 2, pad: CGFloat = 8, rowH: CGFloat = 24
        let size = NSSize(width: (icon.size.width + pad * 2) * scale, height: rowH * 2 * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
        let rows: [(NSAppearance.Name, NSColor)] = [
            (.aqua, NSColor(white: 0.93, alpha: 1)), (.darkAqua, NSColor(white: 0.16, alpha: 1)),
        ]
        for (i, (name, bg)) in rows.enumerated() {
            let y = CGFloat(rows.count - 1 - i) * rowH
            bg.setFill()
            NSRect(x: 0, y: y, width: icon.size.width + pad * 2, height: rowH).fill()
            // Template image: tint it the way the system does (black on light, white on dark).
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                (name == .darkAqua ? NSColor.white : NSColor.black).setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: pad, y: y + (rowH - icon.size.height) / 2,
                                   width: icon.size.width, height: icon.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        let menuURL = URL(fileURLWithPath: url.deletingPathExtension().path + "-menubar.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: menuURL)
    }

    /// Debug hook: with LIMITSBAR_CAPTURE=<file.png> set, the running app saves its real menu bar
    /// item after a refresh. Needs no screen recording permission because it draws its own window.
    static func captureStatusItemIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["LIMITSBAR_CAPTURE"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
                guard let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSLog("LimitsBar: captured status item, appearance %@", window.effectiveAppearance.name.rawValue)
            }
        }
    }

    /// Debug hook: with LIMITSBAR_CAPTURE_MENU=<file.png> set, clicks the status item, saves the
    /// open menu, then closes it. Verifies that a click really opens the menu.
    static func captureMenuIfRequested(button: NSStatusBarButton?, menu: NSMenu) {
        guard let path = ProcessInfo.processInfo.environment["LIMITSBAR_CAPTURE_MENU"], let button else { return }
        nonisolated(unsafe) let menu = menu
        for (i, delay) in [1.5, 6.0].enumerated() {
            let shot = i == 0 ? path.replacingOccurrences(of: ".png", with: "-early.png") : path
            let timer = Timer(timeInterval: delay, repeats: false) { _ in
                MainActor.assumeIsolated {
                    var saved = false
                    for window in NSApp.windows where window.isVisible && String(describing: type(of: window)).contains("Menu") {
                        guard let view = window.contentView?.superview ?? window.contentView,
                              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot))
                        saved = true
                    }
                    NSLog("LimitsBar: menu capture at %.1fs saved=%d windows=%@", delay, saved ? 1 : 0,
                          NSApp.windows.filter(\.isVisible).map { String(describing: type(of: $0)) }.joined(separator: ","))
                    if i == 1 { menu.cancelTracking() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        // Click from a run loop timer, like a real event. Clicking from a main-queue block would
        // keep the main queue (and so the main actor) busy for as long as the menu is open.
        nonisolated(unsafe) let clickTarget = button
        RunLoop.main.add(Timer(timeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated { clickTarget.performClick(nil) }
        }, forMode: .common)
    }
}
