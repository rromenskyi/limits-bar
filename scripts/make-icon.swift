// Draws the app icon and writes Resources/AppIcon.icns plus PNGs for the website.
//   swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let s = CGFloat(px) / 1024
    ctx.cgContext.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt squircle centered in 1024, with a soft drop shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.25, green: 0.30, blue: 0.78, alpha: 1),
                        NSColor(srgbRed: 0.08, green: 0.09, blue: 0.24, alpha: 1)])!
        .draw(in: tile, angle: -90)
    // Faint top sheen.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

    // Four level bars, like the menu bar item.
    let levels: [(CGFloat, NSColor)] = [
        (0.72, .white), (0.18, NSColor(srgbRed: 1.0, green: 0.62, blue: 0.20, alpha: 1)),
        (0.88, .white), (0.55, .white),
    ]
    let barW: CGFloat = 92, gap: CGFloat = 58, barH: CGFloat = 470
    let total = CGFloat(levels.count) * barW + CGFloat(levels.count - 1) * gap
    var x = tile.midX - total / 2
    let y = tile.midY - barH / 2 - 10
    for (level, color) in levels {
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: barH), xRadius: barW / 2, yRadius: barW / 2).fill()
        let h = max(barW, barH * level)
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: h), xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AppIcon-\(UUID().uuidString).iconset"
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(render(base), "\(iconset)/icon_\(base)x\(base).png")
    write(render(base * 2), "\(iconset)/icon_\(base)x\(base)@2x.png")
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconset)

try? fm.createDirectory(atPath: "docs/assets", withIntermediateDirectories: true)
write(render(512), "docs/assets/icon-512.png")
write(render(180), "docs/assets/apple-touch-icon.png")
write(render(64), "docs/assets/favicon-32.png")
write(render(32), "docs/assets/favicon-16.png")
print("wrote Resources/AppIcon.icns and docs/assets icons")
