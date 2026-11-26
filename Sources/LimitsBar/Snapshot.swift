import AppKit
import SwiftUI

@MainActor
enum Snapshot {
    static func write(to url: URL) async {
        _ = NSApplication.shared
        let store = UsageStore(autoStart: false)
        await store.refresh()
        let host = NSHostingView(rootView: UsagePanel(store: store).background(.background))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
