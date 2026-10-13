import CoreGraphics
import Foundation

/// One window on the screens, as macOS lists it.
public struct WindowInfo: Equatable {
    /// The frame in the global coordinates of Core Graphics: the origin is the top-left of the
    /// main display, and y goes down.
    public var frame: CGRect
    /// 0 for the normal windows of apps. The menu bar, the Dock and the desktop have other layers.
    public var layer: Int
    public var ownerPID: pid_t
    public var alpha: CGFloat

    public init(frame: CGRect, layer: Int, ownerPID: pid_t, alpha: CGFloat = 1) {
        self.frame = frame
        self.layer = layer
        self.ownerPID = ownerPID
        self.alpha = alpha
    }
}

/// The window list of the window server. It needs no title, so it needs no permission.
public enum SystemWindowList {
    /// The windows that are on the screens now, from the front to the back.
    public static func windowsOnScreen() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let owner = entry[kCGWindowOwnerPID as String] as? Int
            else { return nil }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            return WindowInfo(frame: frame, layer: layer, ownerPID: pid_t(owner), alpha: CGFloat(alpha))
        }
    }
}

/// The rules of "click a window to select it" (D11). Pure functions.
public enum WindowSnap {
    /// A window that is smaller than this in width or in height is not a target.
    public static let minimumSide: CGFloat = 40

    /// The frames that a click can select, from the front to the back, still in global coordinates:
    /// the normal windows (layer 0) of other apps that are visible and not very small.
    public static func selectableFrames(of windows: [WindowInfo], excludingPID ownPID: pid_t) -> [CGRect] {
        windows
            .filter { window in
                window.layer == 0
                    && window.ownerPID != ownPID
                    && window.alpha > 0
                    && window.frame.width >= minimumSide
                    && window.frame.height >= minimumSide
            }
            .map(\.frame)
    }

    /// The frame of a screen in the global coordinates of Core Graphics, from its AppKit frame.
    /// AppKit has its origin at the bottom-left of the main display, and y goes up.
    public static func globalFrame(ofScreen appKitFrame: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: mainDisplayHeight - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    /// The frames in the points of one screen (the origin is the top-left of that screen).
    /// Each frame is cut to the screen. A window with too little on this screen is left out.
    public static func frames(_ globalFrames: [CGRect], onScreen screen: CGRect) -> [CGRect] {
        globalFrames.compactMap { frame in
            let local = frame.offsetBy(dx: -screen.minX, dy: -screen.minY)
            return Selection(rect: local, in: screen.size)?.rect
        }
    }

    /// The frame that is in front at `point`. `frames` go from the front to the back.
    public static func topFrame(in frames: [CGRect], at point: CGPoint) -> CGRect? {
        frames.first { $0.contains(point) }
    }

    /// What a capture needs: for each screen, the frames that a click can select, in the points
    /// of that screen, from the front to the back.
    public static func framesByDisplay(
        windows: [WindowInfo],
        displays: [FrozenDisplay],
        excludingPID ownPID: pid_t
    ) -> [CGDirectDisplayID: [CGRect]] {
        // The main display is the one with the AppKit origin.
        let mainHeight = displays.first { $0.frame.origin == .zero }?.frame.height
            ?? CGDisplayBounds(CGMainDisplayID()).height
        let selectable = selectableFrames(of: windows, excludingPID: ownPID)
        var result: [CGDirectDisplayID: [CGRect]] = [:]
        for display in displays {
            let screen = globalFrame(ofScreen: display.frame, mainDisplayHeight: mainHeight)
            result[display.displayID] = frames(selectable, onScreen: screen)
        }
        return result
    }
}
