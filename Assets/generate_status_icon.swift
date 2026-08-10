import AppKit

// Generates the menu-bar status icon: a rounded-square frame enclosing a 2×2
// grid of rounded squares, in the spirit of the original Launchpad icon.
// Drawn in black on a transparent background so `isTemplate = true` renders
// it black or white to match the menu bar appearance.
// Run with: swift Assets/generate_status_icon.swift
// Writes Sources/launchPadCore/Resources/StatusIcon.png (36×36, the @2x of an
// 18pt status item).

let canvas: CGFloat = 36
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

NSColor.black.set()
// Outer rounded-square frame.
let frameRect = NSRect(x: 5, y: 5, width: 26, height: 26)
let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 6.5, yRadius: 6.5)
framePath.lineWidth = 3
framePath.stroke()

// 2×2 grid of rounded squares inside the frame.
let cell: CGFloat = 8
let gap: CGFloat = 4
let origin: CGFloat = 8
let radius: CGFloat = 2
for row in 0..<2 {
    for col in 0..<2 {
        let rect = NSRect(
            x: origin + CGFloat(col) * (cell + gap),
            y: origin + CGFloat(row) * (cell + gap),
            width: cell,
            height: cell
        )
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("could not encode icon")
}
let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let output = scriptDir
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/launchPadCore/Resources/StatusIcon.png")
try! png.write(to: output)
print("wrote \(output.path)")
