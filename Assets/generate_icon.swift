import AppKit

// Generates the launchPad app icon: a dark rounded square with a 3×3 grid of
// colorful app tiles, in the spirit of the original Launchpad icon.
// Run with: swift Assets/generate_icon.swift
// Writes /tmp/appicon_1024.png; convert with iconutil (see Assets/README.md).

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let context = NSGraphicsContext.current else {
    fatalError("no graphics context")
}
context.saveGraphicsState()

// Flip into top-left coordinates so drawing math matches screen space.
let flip = NSAffineTransform()
flip.translateX(by: 0, yBy: canvas)
flip.scaleX(by: 1, yBy: -1)
flip.concat()

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// Background squircle.
let backgroundRect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 185, yRadius: 185)
NSGradient(starting: color(0x31406B), ending: color(0x12152A))!
    .draw(in: backgroundPath, angle: -55)

// 3×3 grid of app tiles with distinct colors and SF Symbol glyphs.
let tile: CGFloat = 190
let gap: CGFloat = 48
let origin = (canvas - (tile * 3 + gap * 2)) / 2
let palette: [(top: UInt32, bottom: UInt32, symbol: String)] = [
    (0xFF5F57, 0xC23B2F, "safari"),
    (0xFFB340, 0xE08A00, "envelope.fill"),
    (0x30D158, 0x1E9B3A, "message.fill"),
    (0x40C8E0, 0x1F96AF, "map.fill"),
    (0x5E5CE6, 0x413FB8, "photo.fill"),
    (0x0A84FF, 0x0757C4, "camera.fill"),
    (0xBF5AF2, 0x8C2BC5, "music.note"),
    (0xFF2D55, 0xC31B3D, "calendar"),
    (0x8E8E93, 0x55555A, "gearshape.fill")
]

for row in 0..<3 {
    for col in 0..<3 {
        let entry = palette[row * 3 + col]
        let x = origin + CGFloat(col) * (tile + gap)
        let y = origin + CGFloat(row) * (tile + gap)
        let rect = NSRect(x: x, y: y, width: tile, height: tile)
        let path = NSBezierPath(roundedRect: rect, xRadius: 42, yRadius: 42)
        NSGradient(starting: color(entry.top), ending: color(entry.bottom))!
            .draw(in: path, angle: 90)

        if let symbol = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 84, weight: .medium)) {
            let tinted = NSImage(size: symbol.size)
            tinted.lockFocus()
            symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
            NSColor.white.set()
            NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let glyphRect = NSRect(
                x: rect.midX - symbol.size.width / 2,
                y: rect.midY - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            tinted.draw(in: glyphRect)
        }
    }
}

// Glass highlight over the top portion, clipped to the squircle.
backgroundPath.addClip()
let highlightRect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
NSGradient(
    starting: NSColor.white.withAlphaComponent(0.16),
    ending: NSColor.white.withAlphaComponent(0.0)
)!.draw(in: highlightRect, angle: 90)

context.restoreGraphicsState()
image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("could not encode icon")
}
try! png.write(to: URL(fileURLWithPath: "/tmp/appicon_1024.png"))
print("wrote /tmp/appicon_1024.png")
