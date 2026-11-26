import AppKit
import LimitsBarCore

enum MenuBarStyle: String, CaseIterable {
    case bars, numbers

    var title: String {
        switch self {
        case .bars: "Bars"
        case .numbers: "Numbers"
        }
    }
}

/// Draws the menu bar item: per provider a letter and two stacked mini bars
/// (top: shortest window, bottom: tightest of the longer windows).
///
/// Per the HIG for menu bar extras, this is a template image (black and clear only), so the system
/// tints it for light and dark menu bars and for the selected state. Colors live in the menu.
enum MenuBarIcon {
    struct Item {
        var tag: String
        /// Remaining fractions 0...1; nil means "no data yet".
        var short: Double?
        var long: Double?
        var dimmed: Bool
    }

    static let height: CGFloat = 18
    static let barWidth: CGFloat = 16
    static let barHeight: CGFloat = 3
    static let barGap: CGFloat = 2.5
    static let letterGap: CGFloat = 2
    static let itemGap: CGFloat = 7

    static var font: NSFont { .systemFont(ofSize: 10, weight: .semibold) }

    static func image(for items: [Item]) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let letterWidths = items.map { ceil(($0.tag as NSString).size(withAttributes: attrs).width) }
        let width = items.isEmpty ? height
            : letterWidths.reduce(0, +) + CGFloat(items.count) * (letterGap + barWidth)
              + CGFloat(items.count - 1) * itemGap

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            let label = NSColor.black
            if items.isEmpty {
                let dot = NSBezierPath(ovalIn: NSRect(x: height / 2 - 2, y: height / 2 - 2, width: 4, height: 4))
                label.withAlphaComponent(0.5).setFill()
                dot.fill()
                return true
            }
            var x: CGFloat = 0
            for (item, lw) in zip(items, letterWidths) {
                let alpha: CGFloat = item.dimmed ? 0.45 : 1
                let textAttrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: label.withAlphaComponent(0.9 * alpha),
                ]
                let size = (item.tag as NSString).size(withAttributes: textAttrs)
                (item.tag as NSString).draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: textAttrs)
                x += lw + letterGap

                let stack = barHeight * 2 + barGap
                let top = (height - stack) / 2
                if item.long != nil || item.short == nil {
                    drawBar(x: x, y: top, value: item.short, alpha: alpha)
                    drawBar(x: x, y: top + barHeight + barGap, value: item.long, alpha: alpha)
                } else {
                    // Single window: one thicker bar.
                    drawBar(x: x, y: top, value: item.short, alpha: alpha, height: stack)
                }
                x += barWidth + itemGap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawBar(x: CGFloat, y: CGFloat, value: Double?, alpha: CGFloat, height h: CGFloat = barHeight) {
        let r = h / 2
        let track = NSRect(x: x, y: y, width: barWidth, height: h)
        NSColor.black.withAlphaComponent(0.25 * alpha).setFill()
        NSBezierPath(roundedRect: track, xRadius: r, yRadius: r).fill()
        guard let value else { return }
        let w = max(h, barWidth * CGFloat(min(1, max(0, value))))
        let fill = NSRect(x: x, y: y, width: value <= 0 ? 0 : w, height: h)
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: fill, xRadius: r, yRadius: r).fill()
    }
}
