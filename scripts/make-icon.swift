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

    // The background: a rounded square on the icon grid of macOS (824 of 1024),
    // in the indigo of the Yaseen Docs and Yaseen Draw icons.
    let body = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    NSColor(srgbRed: 0.42, green: 0.40, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: 185 * u, yRadius: 185 * u).fill()

    NSColor.white.setStroke()

    // The glyph is a "Y" that is also a selection box. The two arms of the Y go
    // to the top corners of the box. The bottom corners are the crop marks of a screenshot.
    let box = NSRect(x: 262 * u, y: 262 * u, width: 500 * u, height: 500 * u)
    let arm = 120 * u

    let cropMarks = NSBezierPath()
    cropMarks.lineWidth = 50 * u
    cropMarks.lineCapStyle = .round
    cropMarks.lineJoinStyle = .round
    // Bottom left.
    cropMarks.move(to: NSPoint(x: box.minX, y: box.minY + arm))
    cropMarks.line(to: NSPoint(x: box.minX, y: box.minY))
    cropMarks.line(to: NSPoint(x: box.minX + arm, y: box.minY))
    // Bottom right.
    cropMarks.move(to: NSPoint(x: box.maxX - arm, y: box.minY))
    cropMarks.line(to: NSPoint(x: box.maxX, y: box.minY))
    cropMarks.line(to: NSPoint(x: box.maxX, y: box.minY + arm))
    cropMarks.stroke()

    let letter = NSBezierPath()
    letter.lineWidth = 62 * u
    letter.lineCapStyle = .round
    letter.lineJoinStyle = .round
    let fork = NSPoint(x: box.midX, y: 500 * u)
    letter.move(to: NSPoint(x: box.minX, y: box.maxY))
    letter.line(to: fork)
    letter.move(to: NSPoint(x: box.maxX, y: box.maxY))
    letter.line(to: fork)
    letter.move(to: fork)
    letter.line(to: NSPoint(x: box.midX, y: box.minY))
    letter.stroke()

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
