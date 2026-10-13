import AppKit
import ScreenCaptureKit

/// The still image of one display, taken when a capture starts.
public struct FrozenDisplay {
    public let displayID: CGDirectDisplayID
    /// The image at the pixel size of the display.
    public let image: CGImage
    /// The frame of the `NSScreen`, in points (AppKit coordinates of all screens).
    public let frame: CGRect
    /// Pixels for each point.
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, image: CGImage, frame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.image = image
        self.frame = frame
        self.scale = scale
    }
}

/// The source of the frozen images. The tests use a fake one, so they need no permission.
public protocol ScreenCapturing {
    func freezeAllDisplays() async throws -> [FrozenDisplay]
}

public enum CaptureError: LocalizedError {
    case noDisplay
    case cropFailed

    public var errorDescription: String? {
        switch self {
        case .noDisplay: return "macOS gave no display to capture."
        case .cropFailed: return "The box is not inside the captured image."
        }
    }
}

/// The real capture: ScreenCaptureKit, one image for each display.
public struct SystemScreenCapture: ScreenCapturing {
    public init() {}

    // The displays are captured one after the other on the main actor,
    // because the ScreenCaptureKit types are not Sendable.
    @MainActor
    public func freezeAllDisplays() async throws -> [FrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var frozen: [FrozenDisplay] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            // Each display has its own scale. Ask for exactly its pixels, so the image stays sharp.
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int((screen.frame.width * scale).rounded())
            configuration.height = Int((screen.frame.height * scale).rounded())
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            frozen.append(FrozenDisplay(displayID: displayID, image: image, frame: screen.frame, scale: scale))
        }
        guard !frozen.isEmpty else { throw CaptureError.noDisplay }
        return frozen
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
