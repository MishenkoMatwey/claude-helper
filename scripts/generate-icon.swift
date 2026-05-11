#!/usr/bin/env swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded square background with gradient.
    let radius = s * 0.225  // macOS Big Sur+ icon corner radius
    let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                            xRadius: radius, yRadius: radius)
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(red: 0.36, green: 0.45, blue: 0.95, alpha: 1),  // accent
        NSColor(red: 0.62, green: 0.36, blue: 0.95, alpha: 1)   // purple
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -45)

    // Glow under brain
    ctx.setShadow(offset: .zero, blur: s * 0.06, color: NSColor.white.withAlphaComponent(0.45).cgColor)

    // Draw brain glyph centered, white.
    let symbolConfig = NSImage.SymbolConfiguration(
        pointSize: s * 0.55, weight: .semibold
    )
    if let brain = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = brain.copy() as! NSImage
        tinted.lockFocus()
        NSColor.white.set()
        let r = NSRect(origin: .zero, size: tinted.size)
        r.fill(using: .sourceIn)
        tinted.unlockFocus()
        let drawRect = NSRect(
            x: (s - tinted.size.width) / 2,
            y: (s - tinted.size.height) / 2 - s * 0.015,
            width: tinted.size.width,
            height: tinted.size.height
        )
        tinted.draw(in: drawRect)
    }

    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

for size in sizes {
    let image = renderIcon(size: size)
    writePNG(image, to: "\(outDir)/icon_\(size)x\(size).png")
    if size <= 512 {
        let image2x = renderIcon(size: size * 2)
        writePNG(image2x, to: "\(outDir)/icon_\(size)x\(size)@2x.png")
    }
    print("✓ \(size)x\(size)")
}

print("Run: iconutil -c icns \(outDir) -o AppIcon.icns")
