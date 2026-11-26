import AppKit
import SwiftUI

@MainActor
enum Snapshot {
    /// Writes the panel to `url` and the menu bar item (light and dark, 2x) next to it as `<name>-menubar.png`.
    static func write(to url: URL) async {
        _ = NSApplication.shared
        let store = UsageStore(autoStart: false)
        await store.refresh()

        let host = NSHostingView(rootView: UsagePanel(store: store).background(.background))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }

        let icon = MenuBarIcon.image(for: store.menuBarItems)
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
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                icon.draw(in: NSRect(x: pad, y: y + (rowH - icon.size.height) / 2,
                                     width: icon.size.width, height: icon.size.height))
            }
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
}
