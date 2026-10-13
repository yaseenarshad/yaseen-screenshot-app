import AppKit

/// The content of one overlay window: the frozen image, the dim area, the border and the hint.
///
/// A thin adapter. It turns `NSEvent`s into calls on `CaptureInteraction`, and it draws the state
/// that it reads there. A pointer move changes only two paths; the frozen image is never drawn again.
final class OverlayView: NSView {
    private static let borderColor = CGColor(srgbRed: 0.10, green: 0.55, blue: 1.0, alpha: 1)
    private static let dimColor = CGColor(gray: 0, alpha: 0.45)

    private let display: FrozenDisplay
    private let interaction: CaptureInteraction
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let hintLayer = CALayer()

    init(display: FrozenDisplay, interaction: CaptureInteraction) {
        self.display = display
        self.interaction = interaction
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))

        // The view hosts its own layer tree. The frozen image is the contents of the root layer,
        // at one image pixel for one screen pixel.
        let root = CALayer()
        root.contents = display.image
        root.contentsGravity = .resize
        root.contentsScale = display.scale
        layer = root
        wantsLayer = true

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = OverlayView.dimColor
        borderLayer.fillColor = nil
        borderLayer.strokeColor = OverlayView.borderColor
        borderLayer.lineWidth = 1
        makeHint()

        for sublayer in [dimLayer, borderLayer, hintLayer] {
            sublayer.contentsScale = display.scale
            // No implicit animation: the box must follow the pointer at once.
            sublayer.actions = ["path": NSNull(), "hidden": NSNull(), "position": NSNull(), "bounds": NSNull()]
            root.addSublayer(sublayer)
        }

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Draws the state of the interaction again. Only paths and one flag change.
    func refresh() {
        let box = interaction.selection(on: display.displayID).map { viewRect(for: $0.rect) }

        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let box = box { dim.addRect(box) }
        dimLayer.path = dim

        // The border is outside the box, so it hides no pixel of the box.
        borderLayer.path = box.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }
        hintLayer.isHidden = !interaction.showsHint
    }

    private func makeHint() {
        let text = NSAttributedString(
            string: "Drag to select. Esc to cancel.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
        let textSize = text.size()
        let size = CGSize(width: ceil(textSize.width) + 32, height: ceil(textSize.height) + 16)
        hintLayer.frame = CGRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        hintLayer.backgroundColor = CGColor(gray: 0, alpha: 0.6)
        hintLayer.cornerRadius = 8

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.contentsScale = display.scale
        textLayer.frame = CGRect(x: 16, y: 8, width: ceil(textSize.width), height: ceil(textSize.height))
        hintLayer.addSublayer(textLayer)
    }

    // MARK: Coordinates

    // AppKit has its origin at the bottom-left. `Selection` has its origin at the top-left.
    // These two functions are the only place that changes between them.

    private func selectionPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func viewRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Events

    override var acceptsFirstResponder: Bool { true }

    // A click on the overlay of a different screen must start a drag at once.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = selectionPoint(for: event)
        interaction.pointerDown(at: point, on: display.displayID)
        if event.clickCount == 2 {
            interaction.doubleClick(at: point, on: display.displayID)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        interaction.pointerDragged(to: selectionPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        interaction.pointerUp(at: selectionPoint(for: event))
    }

    override func rightMouseDown(with event: NSEvent) {
        interaction.secondaryClick()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: interaction.key(.enter) // Return, and Enter on the number pad
        case 53: interaction.key(.escape)
        default: break // No call to super: an unknown key must not beep.
        }
    }

    // The pointer is a crosshair on every screen. The cursor rectangle serves the window that has
    // the keyboard. The tracking area serves the windows of the other screens.

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }
}
