import AppKit
import LimitsBarCore

/// The standard About panel, with links to the project and the bundled third-party notices.
@MainActor enum AboutPanel {
    static let project = URL(string: "https://github.com/rromenskyi/limits-bar")!
    static let website = URL(string: "https://rromenskyi.github.io/limits-bar/")!
    static let sponsor = URL(string: "https://github.com/sponsors/rromenskyi")!

    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits(),
            // Version and build are the same number; skip the "(1.2.3)" suffix.
            .version: "",
        ])
    }

    static func credits() -> NSAttributedString {
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let text: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: NSColor.labelColor, .paragraphStyle: centered]

        let out = NSMutableAttributedString()
        let links = [(L("Project Page"), project), (L("Website"), website), (L("Sponsor on GitHub"), sponsor)]
        for (i, (title, url)) in links.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "  ·  ", attributes: text)) }
            out.append(NSAttributedString(string: title, attributes: [.font: small, .link: url, .paragraphStyle: centered]))
        }

        var heading = text
        heading[.font] = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        out.append(NSAttributedString(string: "\n\n" + L("Third-Party Software") + "\n\n", attributes: heading))

        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        out.append(NSAttributedString(string: notices() ?? "THIRD_PARTY_NOTICES.md", attributes: body))
        return out
    }

    /// THIRD_PARTY_NOTICES.md from the bundle as plain text. License texts are hard-wrapped at 80
    /// columns, which the narrow panel would wrap again, so paragraphs are joined into one line.
    static func notices() -> String? {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Notices.plainText(fromMarkdown: raw)
    }

    /// Debug hook: with LIMITSBAR_CAPTURE_ABOUT=<file.png> set, opens the About panel and saves it.
    static func captureIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["LIMITSBAR_CAPTURE_ABOUT"] else { return }
        RunLoop.main.add(Timer(timeInterval: 0.5, repeats: false) { _ in
            MainActor.assumeIsolated { show() }
        }, forMode: .common)
        RunLoop.main.add(Timer(timeInterval: 2, repeats: false) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows where window.isVisible {
                    guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width > 100,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
            }
        }, forMode: .common)
    }
}
