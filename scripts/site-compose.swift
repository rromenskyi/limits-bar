// Composes website images from raw captures (scripts/site-captures.sh).
//   swift scripts/site-compose.swift <raw-dir> docs/assets
import AppKit

let args = CommandLine.arguments
let raw = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let scale: CGFloat = 2

func load(_ name: String) -> NSImage {
    guard let img = NSImage(contentsOf: raw.appendingPathComponent(name)) else { fatalError("missing \(name)") }
    // Captures are 2x bitmaps; size them in points.
    let rep = img.representations[0]
    img.size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
    return img
}

/// Draws into a new bitmap of `size` points at 2x and saves it.
func canvas(_ size: NSSize, _ name: String, jpeg: Bool = false, draw: (NSRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!
                    : rep.representation(using: .png, properties: [:])!
    try! data.write(to: out.appendingPathComponent(name))
    print("wrote \(name)")
}

/// Crops an image to its non-transparent bounds.
func trimmed(_ img: NSImage) -> NSImage {
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    let r = NSRect(x: minX, y: rep.pixelsHigh - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)
    let ptRect = NSRect(x: r.minX / scale, y: r.minY / scale, width: r.width / scale, height: r.height / scale)
    let outImg = NSImage(size: ptRect.size)
    outImg.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: ptRect.size), from: ptRect, operation: .copy, fraction: 1)
    outImg.unlockFocus()
    return outImg
}

/// Recolors a template-style capture (its alpha is the shape) to a solid color.
func tinted(_ img: NSImage, _ color: NSColor) -> NSImage {
    NSImage(size: img.size, flipped: false) { r in
        img.draw(in: r)
        color.setFill()
        r.fill(using: .sourceAtop)
        return true
    }
}

func symbol(_ name: String, _ size: CGFloat, _ color: NSColor) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    return tinted(img, color)
}

func text(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) {
    (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
}

struct Look {
    let dark: Bool
    var name: String { dark ? "dark" : "light" }
    var fg: NSColor { dark ? .white : NSColor(white: 0.08, alpha: 1) }
    var wallpaper: [NSColor] {
        dark ? [NSColor(srgbRed: 0.10, green: 0.11, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.33, green: 0.18, blue: 0.45, alpha: 1),
                NSColor(srgbRed: 0.05, green: 0.25, blue: 0.40, alpha: 1)]
             : [NSColor(srgbRed: 0.72, green: 0.80, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.96, green: 0.80, blue: 0.88, alpha: 1),
                NSColor(srgbRed: 0.80, green: 0.93, blue: 0.96, alpha: 1)]
    }
    var menuBar: NSColor { dark ? NSColor(white: 0, alpha: 0.28) : NSColor(white: 1, alpha: 0.45) }
    var panel: NSColor { dark ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.19, alpha: 0.96) : NSColor(white: 0.97, alpha: 0.97) }
    var border: NSColor { dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.10) }
}

func drawPanel(_ img: NSImage, at origin: NSPoint, look: Look, radius: CGFloat = 11) {
    let rect = NSRect(origin: origin, size: img.size)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(look.dark ? 0.55 : 0.25)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    look.panel.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    look.panel.setFill()
    path.fill()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    img.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    look.border.setStroke()
    path.lineWidth = 0.5
    path.stroke()
}

// Menu bar item renderings, same geometry as Sources/LimitsBar/MenuBarIcon.swift, demo values.
let demo: [(String, CGFloat, CGFloat)] = [("C", 0.72, 0.58), ("X", 0.64, 0.18), ("M", 0.88, 0.44), ("D", 1.0, 0.91)]

func compactIcon(_ color: NSColor) -> NSImage {
    let w: CGFloat = 3.5, gap: CGFloat = 2.5, h: CGFloat = 14
    let size = NSSize(width: CGFloat(demo.count) * w + CGFloat(demo.count - 1) * gap, height: 18)
    return NSImage(size: size, flipped: false) { _ in
        for (i, d) in demo.enumerated() {
            let x = CGFloat(i) * (w + gap), y: CGFloat = 2
            color.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: w / 2, yRadius: w / 2).fill()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: max(w, h * min(d.1, d.2))),
                         xRadius: w / 2, yRadius: w / 2).fill()
        }
        return true
    }
}

func barsIcon(_ color: NSColor) -> NSImage {
    let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    let bw: CGFloat = 16, bh: CGFloat = 3, bgap: CGFloat = 2.5, lgap: CGFloat = 2, igap: CGFloat = 7
    let widths = demo.map { ceil(($0.0 as NSString).size(withAttributes: [.font: font]).width) }
    let size = NSSize(width: widths.reduce(0, +) + CGFloat(demo.count) * (lgap + bw) + CGFloat(demo.count - 1) * igap, height: 18)
    return NSImage(size: size, flipped: true) { _ in
        var x: CGFloat = 0
        for (d, lw) in zip(demo, widths) {
            let ts = (d.0 as NSString).size(withAttributes: [.font: font])
            (d.0 as NSString).draw(at: NSPoint(x: x, y: (18 - ts.height) / 2),
                                   withAttributes: [.font: font, .foregroundColor: color.withAlphaComponent(0.9)])
            x += lw + lgap
            let top = (18 - (bh * 2 + bgap)) / 2
            for (j, v) in [d.1, d.2].enumerated() {
                let y = top + CGFloat(j) * (bh + bgap)
                color.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: bw, height: bh), xRadius: bh / 2, yRadius: bh / 2).fill()
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: max(bh, bw * v), height: bh), xRadius: bh / 2, yRadius: bh / 2).fill()
            }
            x += bw + igap
        }
        return true
    }
}

func numbersIcon(_ color: NSColor) -> NSImage {
    let s = demo.map { "\($0.0)\(Int((min($0.1, $0.2) * 100).rounded()))" }.joined(separator: " ")
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                                                .foregroundColor: color]
    let size = (s as NSString).size(withAttributes: attrs)
    return NSImage(size: NSSize(width: ceil(size.width), height: 18), flipped: false) { _ in
        (s as NSString).draw(at: NSPoint(x: 0, y: (18 - size.height) / 2), withAttributes: attrs)
        return true
    }
}

// Hero: desktop, menu bar with the item selected, menu open beneath it.
for look in [Look(dark: true), Look(dark: false)] {
    let menu = load("menu-\(look.name).png")
    let size = NSSize(width: 860, height: menu.size.height + 28 + 70)
    canvas(size, "hero-\(look.name).png") { r in
        NSGradient(colors: look.wallpaper)!.draw(in: r, angle: -35)
        // Soft light blobs for depth.
        for (c, p, rad) in [(NSColor.white.withAlphaComponent(look.dark ? 0.06 : 0.25), NSPoint(x: 220, y: 180), 260.0),
                            (NSColor.white.withAlphaComponent(look.dark ? 0.05 : 0.20), NSPoint(x: 820, y: 520), 300.0)] {
            NSGradient(colors: [c, c.withAlphaComponent(0)])!.draw(fromCenter: p, radius: 0, toCenter: p, radius: rad, options: [])
        }
        let barH: CGFloat = 28
        let top = r.height - barH
        look.menuBar.setFill()
        NSRect(x: 0, y: top, width: r.width, height: barH).fill()

        let menuFont = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        symbol("apple.logo", 14, look.fg).draw(at: NSPoint(x: 18, y: top + 6), from: .zero, operation: .sourceOver, fraction: 1)
        text("Finder", .systemFont(ofSize: 13.5, weight: .bold), look.fg, at: NSPoint(x: 46, y: top + 5))
        var x: CGFloat = 104
        for item in ["File", "Edit", "View", "Go", "Window", "Help"] {
            text(item, menuFont, look.fg, at: NSPoint(x: x, y: top + 5))
            x += (item as NSString).size(withAttributes: [.font: menuFont]).width + 20
        }

        // Right side: clock, battery, wifi, then our item (selected).
        let clock = "Thu Nov 26  9:41 AM"
        let clockW = (clock as NSString).size(withAttributes: [.font: menuFont]).width
        var rx = r.width - 16 - clockW
        text(clock, menuFont, look.fg, at: NSPoint(x: rx, y: top + 5))
        for name in ["battery.75percent", "wifi"] {
            let s = symbol(name, 14, look.fg)
            rx -= s.size.width + 16
            s.draw(at: NSPoint(x: rx, y: top + (barH - s.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
        }
        let icon = compactIcon(look.fg)
        let pillW = icon.size.width + 16
        rx -= pillW + 12
        let pill = NSRect(x: rx, y: top + 3, width: pillW, height: barH - 6)
        (look.dark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.12)).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        icon.draw(at: NSPoint(x: pill.midX - icon.size.width / 2, y: pill.midY - icon.size.height / 2),
                  from: .zero, operation: .sourceOver, fraction: 1)

        // Like macOS, keep the menu on screen: shift it left if it would run off the edge.
        let menuX = min(pill.minX - 8, r.width - menu.size.width - 10)
        drawPanel(menu, at: NSPoint(x: menuX, y: top - 6 - menu.size.height), look: look)
    }
}

// Menu bar styles, for each look: the item alone, cropped tight (HTML lays them out).
for look in [Look(dark: true), Look(dark: false)] {
    for (name, make) in [("compact", compactIcon), ("bars", barsIcon), ("numbers", numbersIcon)] {
        let t = make(look.fg)
        canvas(NSSize(width: t.size.width + 24, height: 30), "style-\(name)-\(look.name).png") { r in
            look.menuBar.withAlphaComponent(0).setFill()
            t.draw(at: NSPoint(x: 12, y: (r.height - t.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

// Translated menus: the usage rows only.
for lang in ["ru", "ja", "de"] {
    let menu = load("menu-\(lang).png")
    let rowsHeight: CGFloat = 340
    let crop = NSImage(size: NSSize(width: menu.size.width, height: rowsHeight))
    crop.lockFocus()
    menu.draw(in: NSRect(origin: .zero, size: crop.size),
              from: NSRect(x: 0, y: menu.size.height - rowsHeight, width: menu.size.width, height: rowsHeight),
              operation: .copy, fraction: 1)
    crop.unlockFocus()
    let look = Look(dark: true)
    canvas(NSSize(width: crop.size.width + 60, height: rowsHeight + 60), "lang-\(lang).png") { _ in
        drawPanel(crop, at: NSPoint(x: 30, y: 34), look: look)
    }
}

// Social preview card.
let iconImg = NSImage(contentsOf: out.appendingPathComponent("icon-512.png"))!
canvas(NSSize(width: 1200, height: 630), "og-image.jpg", jpeg: true) { r in
    let look = Look(dark: true)
    NSGradient(colors: look.wallpaper)!.draw(in: r, angle: -35)
    iconImg.draw(in: NSRect(x: 70, y: 380, width: 150, height: 150))
    text("LimitsBar", .systemFont(ofSize: 76, weight: .bold), .white, at: NSPoint(x: 70, y: 250))
    let sub = NSFont.systemFont(ofSize: 30, weight: .regular)
    text("Claude, Codex, Muse and Devin limits", sub, NSColor(white: 1, alpha: 0.85), at: NSPoint(x: 72, y: 196))
    text("in your Mac's menu bar.", sub, NSColor(white: 1, alpha: 0.85), at: NSPoint(x: 72, y: 156))
    // Right: the whole menu panel, scaled to fit.
    let menu = load("menu-dark.png")
    let k: CGFloat = 560 / menu.size.height
    let scaled = NSImage(size: NSSize(width: menu.size.width * k, height: menu.size.height * k), flipped: false) { r in
        menu.draw(in: r); return true
    }
    drawPanel(scaled, at: NSPoint(x: 1200 - scaled.size.width - 80, y: 35), look: look)
}
