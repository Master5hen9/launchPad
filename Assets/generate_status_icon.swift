import AppKit

// Generates the menu-bar status icon: a simple monochrome 2×2 grid of rounded
// squares in the spirit of the original Launchpad icon. Drawn in black on a
// transparent background so `isTemplate = true` renders it black or white to
// match the menu bar appearance.
// Run with: swift Assets/generate_status_icon.swift
// Writes Sources/launchPadCore/Resources/StatusIcon.png (36×36, the @2x of an
// 18pt status item).

let canvas: CGFloat = 36
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

NSColor.black.set()
let cell: CGFloat = 9
let gap: CGFloat = 4
let origin: CGFloat = 7
let radius: CGFloat = 2.5
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
