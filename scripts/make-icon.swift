// Draws the app icon and writes `Support/AppIcon.icns`.
//
// USAGE (from the repository root):
//   swift scripts/make-icon.swift
//
// The script draws each size of the icon into `build/AppIcon.iconset`, then
// `iconutil` packs the sizes into `Support/AppIcon.icns`. It uses only AppKit
// and tools that come with Xcode. Run it again after a change to the drawing.

import AppKit

/// Draws the icon into a square of `pixels` x `pixels`.
func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // All the numbers below are for a 1024 canvas. `u` scales them.
    let u = CGFloat(pixels) / 1024.0

    // The background: a rounded square on the icon grid of macOS (824 of 1024).
    let body = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let background = NSBezierPath(roundedRect: body, xRadius: 185 * u, yRadius: 185 * u)
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.24, green: 0.60, blue: 1.00, alpha: 1),
        ending: NSColor(srgbRed: 0.05, green: 0.30, blue: 0.85, alpha: 1)
    )!
    gradient.draw(in: background, angle: -90)

    NSColor.white.setStroke()
    NSColor.white.setFill()

    // The glyph: the four corners of a selection box.
    let box = NSRect(x: 290 * u, y: 290 * u, width: 444 * u, height: 444 * u)
    let arm = 130 * u
    let corners = NSBezierPath()
    corners.lineWidth = 56 * u
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    // Bottom left.
    corners.move(to: NSPoint(x: box.minX, y: box.minY + arm))
    corners.line(to: NSPoint(x: box.minX, y: box.minY))
    corners.line(to: NSPoint(x: box.minX + arm, y: box.minY))
    // Bottom right.
    corners.move(to: NSPoint(x: box.maxX - arm, y: box.minY))
    corners.line(to: NSPoint(x: box.maxX, y: box.minY))
    corners.line(to: NSPoint(x: box.maxX, y: box.minY + arm))
    // Top right.
    corners.move(to: NSPoint(x: box.maxX, y: box.maxY - arm))
    corners.line(to: NSPoint(x: box.maxX, y: box.maxY))
    corners.line(to: NSPoint(x: box.maxX - arm, y: box.maxY))
    // Top left.
    corners.move(to: NSPoint(x: box.minX + arm, y: box.maxY))
    corners.line(to: NSPoint(x: box.minX, y: box.maxY))
    corners.line(to: NSPoint(x: box.minX, y: box.maxY - arm))
    corners.stroke()

    // The lens: a ring with a dot in the middle of the box.
    let ringRadius = 92 * u
    let ring = NSBezierPath(ovalIn: NSRect(
        x: box.midX - ringRadius, y: box.midY - ringRadius,
        width: ringRadius * 2, height: ringRadius * 2
    ))
    ring.lineWidth = 44 * u
    ring.stroke()

    let dotRadius = 26 * u
    NSBezierPath(ovalIn: NSRect(
        x: box.midX - dotRadius, y: box.midY - dotRadius,
        width: dotRadius * 2, height: dotRadius * 2
    )).fill()

    return rep
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
guard fileManager.fileExists(atPath: root.appendingPathComponent("Support/Info.plist").path) else {
    fail("run this script from the repository root: swift scripts/make-icon.swift")
}

let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let output = root.appendingPathComponent("Support/AppIcon.icns")

try? fileManager.removeItem(at: iconset)
do {
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
} catch {
    fail("cannot make \(iconset.path): \(error)")
}

// The file names and pixel sizes that `iconutil` expects.
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for entry in entries {
    let rep = drawIcon(pixels: entry.pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("cannot make the PNG data for \(entry.name)")
    }
    do {
        try png.write(to: iconset.appendingPathComponent(entry.name))
    } catch {
        fail("cannot write \(entry.name): \(error)")
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
do {
    try iconutil.run()
} catch {
    fail("cannot start iconutil: \(error)")
}
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil failed with status \(iconutil.terminationStatus)")
}

try? fileManager.removeItem(at: iconset)
print("Wrote \(output.path)")
