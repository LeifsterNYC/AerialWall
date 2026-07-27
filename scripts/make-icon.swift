// Generates Resources/AppIcon.icns: white mountain symbol on a blue squircle.
//   swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Big Sur icon grid: 824pt squircle centered on a 1024pt transparent canvas.
let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 185, yRadius: 185
)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.05, green: 0.32, blue: 0.65, alpha: 1),
    ending: NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.92, alpha: 1)
)!
gradient.draw(in: squircle, angle: 90)

let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
if let symbol = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let size = NSSize(width: 560, height: 560 * symbol.size.height / symbol.size.width)
    tinted.draw(
        in: NSRect(
            x: (canvas - size.width) / 2,
            y: (canvas - size.height) / 2,
            width: size.width, height: size.height
        ),
        from: .zero, operation: .sourceOver, fraction: 1
    )
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon")
}
let base = URL(fileURLWithPath: "scripts").deletingLastPathComponent()
let out = URL(fileURLWithPath: "icon-1024.png")
try! png.write(to: out)
print("wrote \(out.path)")
