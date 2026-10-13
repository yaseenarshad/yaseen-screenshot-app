import CoreGraphics

/// The keys that a capture understands. The view maps key codes to these.
public enum CaptureKey {
    case enter
    case escape
}

/// What a finished capture hands over: enough to make the final image.
public struct CaptureResult {
    public let display: FrozenDisplay
    public let selection: Selection
    public let marks: MarkList
}

public enum CaptureOutcome {
    case done(CaptureResult)
    case cancel
}

/// The state of one capture, with no window and no view.
///
/// One instance serves all screens, because only one box exists at a time.
/// The view is a thin adapter: it turns `NSEvent`s into these calls and draws what it reads here.
/// Every point is in the points of its screen, with the origin at the top-left of that screen.
public final class CaptureInteraction {
    /// A pointer that moved less than this is a click, not a drag.
    public static let minimumDrag: CGFloat = 3

    public let displays: [FrozenDisplay]
    public private(set) var marks = MarkList()

    /// Called after the box changed. The views draw again.
    public var onChange: (() -> Void)?
    /// Called one time, when the capture ends.
    public var onFinish: ((CaptureOutcome) -> Void)?

    private var box: (display: FrozenDisplay, selection: Selection)?
    private var drag: (display: FrozenDisplay, start: CGPoint, isPastMinimum: Bool)?
    private var isFinished = false

    public init(displays: [FrozenDisplay]) {
        self.displays = displays
    }

    // MARK: What the views read

    /// The box on the given screen, or `nil` when the box is on a different screen or does not exist.
    public func selection(on displayID: CGDirectDisplayID) -> Selection? {
        box?.display.displayID == displayID ? box?.selection : nil
    }

    /// The screen that has the box.
    public var selectionDisplayID: CGDirectDisplayID? {
        box?.display.displayID
    }

    /// The text "Drag to select" shows on every screen while no box exists.
    public var showsHint: Bool {
        box == nil
    }

    // MARK: The calls of the views

    public func pointerDown(at point: CGPoint, on displayID: CGDirectDisplayID) {
        drag = nil
        guard !isFinished, let display = displays.first(where: { $0.displayID == displayID }) else { return }
        // A pointer down in the box does not start a new box. Subissue 2 makes it move the box.
        if selection(on: displayID)?.contains(point) == true { return }
        drag = (display, point, false)
    }

    public func pointerDragged(to point: CGPoint) {
        guard !isFinished, var drag = drag else { return }
        if !drag.isPastMinimum {
            let distance = hypot(point.x - drag.start.x, point.y - drag.start.y)
            guard distance >= CaptureInteraction.minimumDrag else { return }
            drag.isPastMinimum = true
            self.drag = drag
        }
        // The box stays on the screen of the pointer down, also when the pointer leaves that screen.
        let selection = Selection(from: drag.start, to: point, in: drag.display.frame.size)
        guard box?.display.displayID != drag.display.displayID || box?.selection != selection else { return }
        box = (drag.display, selection)
        onChange?()
    }

    public func pointerUp(at point: CGPoint) {
        pointerDragged(to: point)
        drag = nil
    }

    public func doubleClick(at point: CGPoint, on displayID: CGDirectDisplayID) {
        guard selection(on: displayID)?.contains(point) == true else { return }
        finishWithBox()
    }

    /// A right-click: it removes the box, or cancels when no box exists.
    public func secondaryClick() {
        guard !isFinished else { return }
        drag = nil
        if box == nil {
            finish(.cancel)
        } else {
            box = nil
            onChange?()
        }
    }

    public func key(_ key: CaptureKey) {
        switch key {
        case .enter: finishWithBox()
        case .escape: cancel()
        }
    }

    public func cancel() {
        finish(.cancel)
    }

    // MARK: The end

    private func finishWithBox() {
        guard let box = box else { return }
        finish(.done(CaptureResult(display: box.display, selection: box.selection, marks: marks)))
    }

    private func finish(_ outcome: CaptureOutcome) {
        guard !isFinished else { return }
        isFinished = true
        drag = nil
        onFinish?(outcome)
    }
}
