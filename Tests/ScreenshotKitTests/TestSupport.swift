import AppKit
import ScreenshotKit

// Shared helpers. Everything here stays out of sight: no window, no real screen,
// no general pasteboard, no file outside a temporary folder.

struct Pixel: Equatable, CustomStringConvertible {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    var description: String { "(\(red), \(green), \(blue))" }
}

/// The colour of the test image at one pixel (top-left origin). Each pixel differs from its
/// neighbours, so a crop that is off by one pixel, or upside down, gives a wrong colour.
func patternPixel(x: Int, y: Int) -> Pixel {
    Pixel(red: UInt8(x % 251), green: UInt8(y % 241), blue: UInt8((x + y) % 239))
}

func makePatternImage(width: Int, height: Int) -> CGImage {
    makeImage(width: width, height: height, pixel: patternPixel)
}

/// An image with the colour that `pixel` gives for each pixel (top-left origin).
func makeImage(width: Int, height: Int, pixel: (_ x: Int, _ y: Int) -> Pixel) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let pixel = pixel(x, y)
            let offset = (y * width + x) * 4
            bytes[offset] = pixel.red
            bytes[offset + 1] = pixel.green
            bytes[offset + 2] = pixel.blue
        }
    }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

extension Pixel {
    static let white = Pixel(red: 255, green: 255, blue: 255)
    static let black = Pixel(red: 0, green: 0, blue: 0)

    /// The colour of a mark, as a pixel.
    init(_ color: MarkColor) {
        let parts = color.components
        self.init(
            red: UInt8((parts.red * 255).rounded()),
            green: UInt8((parts.green * 255).rounded()),
            blue: UInt8((parts.blue * 255).rounded())
        )
    }

    /// True when each part differs by `tolerance` at most. A drawn edge is not exact to the last bit.
    func isNear(_ other: Pixel, tolerance: Int = 3) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance
            && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
    }
}

/// Reads one pixel of an image (top-left origin).
struct PixelReader {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { pointer in
            let context = CGContext(
                data: pointer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    subscript(x: Int, y: Int) -> Pixel {
        let offset = (y * width + x) * 4
        return Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
    }
}

/// The capture of the tests: fixed images, and no permission.
struct FakeScreenCapture: ScreenCapturing {
    /// Display 1 has scale 2 and display 2 has scale 1, the same mix as the two real monitors.
    static let retinaID: CGDirectDisplayID = 1
    static let plainID: CGDirectDisplayID = 2

    func freezeAllDisplays() async throws -> [FrozenDisplay] {
        [
            FrozenDisplay(
                displayID: FakeScreenCapture.retinaID,
                image: makePatternImage(width: 400, height: 200),
                frame: CGRect(x: 0, y: 0, width: 200, height: 100),
                scale: 2
            ),
            FrozenDisplay(
                displayID: FakeScreenCapture.plainID,
                image: makePatternImage(width: 300, height: 150),
                frame: CGRect(x: 200, y: 0, width: 300, height: 150),
                scale: 1
            ),
        ]
    }
}

/// A temporary folder and a private pasteboard for one test.
final class Sandbox {
    let folder: URL
    let pasteboard: NSPasteboard

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YaseenScreenshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.yaseenarshad.yaseenscreenshot.tests.\(UUID().uuidString)"))
    }

    deinit {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
    }

    var fileNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }
}

/// Noon on a local day, so the day of the file name is the same in each time zone.
func localDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}
