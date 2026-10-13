import AppKit

/// The content of one overlay window: the frozen image, the dim area, the box with its handles
/// and its label, the marks, the toolbar and the text field.
///
/// A thin adapter. It turns `NSEvent`s into calls on `CaptureInteraction`, and it draws the state
/// that it reads there. A pointer move changes only paths and frames. Only a change of the marks
/// makes an image again, and that image has the size of the box. The frozen image is never drawn again.
final class OverlayView: NSView, NSTextViewDelegate {
    private static let borderColor = CGColor(srgbRed: 0.10, green: 0.55, blue: 1.0, alpha: 1)
    private static let dimColor = CGColor(gray: 0, alpha: 0.45)
    /// The side of a handle that the user sees. Its hit area is larger (`Selection.handleHitSide`).
    private static let handleSide: CGFloat = 7
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private let display: FrozenDisplay
    private let interaction: CaptureInteraction

    // AppKit does not support subviews in a view that hosts its own layers. Thus the layers are in
    // `canvas`, and the toolbar and the text field are its siblings above it.
    private let canvas = NSView()
    /// The root of the layers: the frozen image. The tests draw this layer into a bitmap.
    let canvasLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let marksLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let labelLayer = CALayer()
    private let labelTextLayer = CATextLayer()
    private let hintLayer = CALayer()
    let toolbar: Toolbar

    /// The field of the text that is open. `nil` when the user types no text.
    private(set) var textView: NSTextView?
    private var textLayout: TextLayout?
    private var shownTextEdit: TextEdit?
    private var shownMarks: (revision: Int, rect: CGRect)?
    private var shownLabel = ""
    private var cursor = NSCursor.crosshair

    init(display: FrozenDisplay, interaction: CaptureInteraction) {
        self.display = display
        self.interaction = interaction
        toolbar = Toolbar(interaction: interaction)
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        wantsLayer = true

        // The canvas hosts its own layer tree. The frozen image is the contents of the root layer,
        // at one image pixel for one screen pixel.
        let root = canvasLayer
        root.contents = display.image
        root.contentsGravity = .resize
        root.contentsScale = display.scale
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.layer = root
        canvas.wantsLayer = true
        addSubview(canvas)

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = OverlayView.dimColor
        marksLayer.contentsGravity = .resize
        marksLayer.magnificationFilter = .nearest
        borderLayer.fillColor = nil
        borderLayer.strokeColor = OverlayView.borderColor
        borderLayer.lineWidth = 1
        handlesLayer.fillColor = .white
        handlesLayer.strokeColor = OverlayView.borderColor
        handlesLayer.lineWidth = 1
        labelLayer.backgroundColor = CGColor(gray: 0, alpha: 0.7)
        labelLayer.cornerRadius = 3
        labelLayer.addSublayer(labelTextLayer)
        makeHint()

        // No implicit animation: the box must follow the pointer at once.
        let noActions: [String: CAAction] = [
            "path": NSNull(), "hidden": NSNull(), "position": NSNull(), "bounds": NSNull(),
            "contents": NSNull(), "string": NSNull(),
        ]
        for sublayer in [dimLayer, marksLayer, borderLayer, handlesLayer, labelLayer, hintLayer] {
            sublayer.contentsScale = display.scale
            sublayer.actions = noActions
            root.addSublayer(sublayer)
        }
        labelTextLayer.contentsScale = display.scale
        labelTextLayer.actions = noActions

        toolbar.isHidden = true
        addSubview(toolbar)

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

    // MARK: Drawing the state

    /// Shows the state of the interaction again.
    func refresh() {
        let selection = interaction.selection(on: display.displayID)
        let box = selection.map { viewRect(for: $0.rect) }
        // Before a box exists, the window below the pointer is bright in the same way as a box.
        let bright = box ?? interaction.highlight(on: display.displayID).map(viewRect(for:))

        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let bright = bright { dim.addRect(bright) }
        dimLayer.path = dim

        // The border is outside the box, so it hides no pixel of the box.
        borderLayer.path = bright.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }
        handlesLayer.path = interaction.showsHandles ? box.map(handlesPath(around:)) : nil
        hintLayer.isHidden = !interaction.showsHint

        var toolbarFrame = CGRect.null
        if let selection = selection, interaction.showsToolbar(on: display.displayID) {
            toolbar.refresh()
            toolbarFrame = selection.toolbarFrame(
                size: toolbar.frame.size, tallestHeight: Toolbar.tallestHeight, in: bounds.size
            )
            toolbar.setFrameOrigin(viewRect(for: toolbarFrame).origin)
            toolbar.isHidden = false
        } else {
            toolbar.isHidden = true
        }

        refreshLabel(for: selection, avoiding: toolbarFrame)
        refreshMarks(in: selection)
        refreshTextView(in: selection)
    }

    /// Eight squares on the border: the four corners and the four edge middles.
    private func handlesPath(around box: CGRect) -> CGPath {
        // The squares sit on the middle of the 1 point border, on whole points.
        let line = box.insetBy(dx: -0.5, dy: -0.5)
        let half = OverlayView.handleSide / 2
        let path = CGMutablePath()
        for x in [line.minX, line.midX, line.maxX] {
            for y in [line.minY, line.midY, line.maxY] where !(x == line.midX && y == line.midY) {
                let square = CGRect(
                    x: (x - half).rounded(.down),
                    y: (y - half).rounded(.down),
                    width: OverlayView.handleSide,
                    height: OverlayView.handleSide
                )
                // The 1 point edge is inside the square, so it is sharp at scale 1.
                path.addRect(square.insetBy(dx: 0.5, dy: 0.5))
            }
        }
        return path
    }

    private func refreshLabel(for selection: Selection?, avoiding toolbarFrame: CGRect) {
        guard let selection = selection else {
            labelLayer.isHidden = true
            return
        }
        let text = NSAttributedString(string: selection.sizeText, attributes: OverlayView.labelAttributes)
        let textSize = text.size()
        let textWidth = ceil(textSize.width), textHeight = ceil(textSize.height)
        let frame = selection.labelFrame(
            labelSize: CGSize(width: textWidth + 10, height: textHeight + 4), in: bounds.size, avoiding: toolbarFrame
        )
        labelLayer.frame = viewRect(for: frame)
        if shownLabel != selection.sizeText {
            shownLabel = selection.sizeText
            labelTextLayer.frame = CGRect(x: 5, y: 2, width: textWidth, height: textHeight)
            labelTextLayer.string = text
        }
        labelLayer.isHidden = false
    }

    /// The marks show as one image in the box: the box of the frozen image with the marks, made by
    /// the code that makes the saved image. Highlight needs the pixels below it, so a transparent
    /// layer is not enough.
    private func refreshMarks(in selection: Selection?) {
        let marks = interaction.visibleMarks
        guard let selection = selection, !marks.isEmpty else {
            marksLayer.isHidden = true
            marksLayer.contents = nil
            shownMarks = nil
            return
        }
        guard shownMarks?.revision != interaction.marksRevision || shownMarks?.rect != selection.rect else { return }
        marksLayer.frame = viewRect(for: selection.rect)
        marksLayer.contents = try? composeImage(frozen: display, selection: selection, marks: marks)
        marksLayer.isHidden = false
        shownMarks = (interaction.marksRevision, selection.rect)
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

    // MARK: The text field

    private func refreshTextView(in selection: Selection?) {
        guard let selection = selection, let edit = interaction.textEdit else {
            removeTextView()
            return
        }
        if textView == nil || shownTextEdit?.origin != edit.origin {
            removeTextView()
            makeTextView(for: edit, in: selection)
        } else if shownTextEdit?.style != edit.style, let textView = textView {
            apply(edit.style, to: textView)
        }
        shownTextEdit = edit
    }

    private func makeTextView(for edit: TextEdit, in selection: Selection) {
        // The same layout as `MarkRenderer`, so the lines break where the saved image breaks them.
        let layout = TextLayout(text: "", style: edit.style, wrapWidth: edit.wrapWidth)
        let box = viewRect(for: selection.rect)
        // From the place of the text to the right and the bottom edge of the box.
        let frame = CGRect(
            x: box.minX + edit.origin.x,
            y: box.minY,
            width: edit.wrapWidth,
            height: max(selection.rect.height - edit.origin.y, 1)
        )
        let field = NSTextView(frame: frame, textContainer: layout.container)
        field.delegate = self
        field.drawsBackground = false
        field.isRichText = false
        field.allowsUndo = true
        field.textContainerInset = .zero
        field.isVerticallyResizable = false
        field.isHorizontallyResizable = false
        field.clipsToBounds = true
        field.focusRingType = .none
        // The user types a label, not prose. macOS must not change what was typed.
        field.isAutomaticSpellingCorrectionEnabled = false
        field.isAutomaticTextReplacementEnabled = false
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.isAutomaticDashSubstitutionEnabled = false
        field.isContinuousSpellCheckingEnabled = false
        apply(edit.style, to: field)

        addSubview(field, positioned: .below, relativeTo: toolbar)
        textView = field
        textLayout = layout
        // The typing goes to the window that has the keyboard. The panel takes it with no app switch.
        if let window = window, window.isVisible, !window.isKeyWindow {
            window.makeKey()
        }
        window?.makeFirstResponder(field)
    }

    private func apply(_ style: MarkStyle, to field: NSTextView) {
        let attributes = MarkRenderer.textAttributes(style)
        field.font = attributes[.font] as? NSFont
        field.textColor = attributes[.foregroundColor] as? NSColor
        field.insertionPointColor = (attributes[.foregroundColor] as? NSColor) ?? .red
        field.typingAttributes = attributes
    }

    private func removeTextView() {
        guard let field = textView else { return }
        textView = nil
        textLayout = nil
        shownTextEdit = nil
        if window?.firstResponder === field {
            window?.makeFirstResponder(self)
        }
        field.delegate = nil
        field.removeFromSuperview()
    }

    func textDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextView, field === textView else { return }
        interaction.textChanged(field.string)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            // Return completes the text. Option-Return still makes a new line.
            interaction.completeText()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            interaction.key(.escape)
            return true
        default:
            return false
        }
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

    /// The toolbar takes its own clicks. The text field takes a click on its text, to move the
    /// caret. Each other click is for the interaction: it draws, or it completes the text.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit.isDescendant(of: toolbar) { return hit }
        if let field = textView, let layout = textLayout, hit.isDescendant(of: field),
           layout.usedRect.insetBy(dx: -4, dy: -2).contains(field.convert(point, from: superview)) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = selectionPoint(for: event)
        interaction.pointerDown(at: point, on: display.displayID)
        if event.clickCount == 2 {
            interaction.doubleClick(at: point, on: display.displayID)
        }
        updateCursor(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        interaction.pointerDragged(to: selectionPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        let point = selectionPoint(for: event)
        interaction.pointerUp(at: point)
        interaction.pointerMoved(to: point, on: display.displayID)
        updateCursor(at: point)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = selectionPoint(for: event)
        interaction.pointerMoved(to: point, on: display.displayID)
        interaction.secondaryClick()
        updateCursor(at: point)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = selectionPoint(for: event)
        interaction.pointerMoved(to: point, on: display.displayID)
        updateCursor(at: point)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: interaction.key(.enter) // Return, and Enter on the number pad
        case 53: interaction.key(.escape)
        default: break // No call to super: an unknown key must not beep.
        }
    }

    /// Command-Z and Shift-Command-Z. The app has no Edit menu, so the keys of the menu come here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, flags.contains(.command), !flags.contains(.control), !flags.contains(.option)
        else { return super.performKeyEquivalent(with: event) }
        // Some keyboard layouts give the Latin letter only in `characters`.
        let keys = [event.charactersIgnoringModifiers, event.characters].map { $0?.lowercased() }
        let isShift = flags.contains(.shift)

        if let field = textView {
            // While a text is open, the keys are for the typing.
            if keys.contains("z") {
                if isShift { field.undoManager?.redo() } else { field.undoManager?.undo() }
            } else if keys.contains("v") {
                field.pasteAsPlainText(nil)
            } else if keys.contains("c") {
                field.copy(nil)
            } else if keys.contains("x") {
                field.cut(nil)
            } else if keys.contains("a") {
                field.selectAll(nil)
            } else {
                return super.performKeyEquivalent(with: event)
            }
            return true
        }
        guard keys.contains("z") else { return super.performKeyEquivalent(with: event) }
        interaction.key(isShift ? .redo : .undo)
        return true
    }

    // MARK: The pointer shape

    // The shape tells what a drag does: a crosshair outside the box, an open hand inside, and
    // resize arrows on a handle. The cursor rectangle always holds the current shape, so AppKit
    // and this view never set different shapes.

    private func updateCursor(at point: CGPoint) {
        let isOnToolbar = !toolbar.isHidden && toolbar.frame.contains(CGPoint(x: point.x, y: bounds.height - point.y))
        let shape = isOnToolbar ? .arrow : interaction.pointerShape(at: point, on: display.displayID)
        let next = OverlayView.cursor(for: shape)
        if next !== cursor {
            cursor = next
            window?.invalidateCursorRects(for: self)
        }
        next.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: selectionPoint(for: event))
    }

    private static var resizeCursors: [Handle: NSCursor] = [:]

    static func cursor(for shape: PointerShape) -> NSCursor {
        switch shape {
        case .crosshair: return .crosshair
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .iBeam: return .iBeam
        case .arrow: return .arrow
        case .resize(let handle):
            if let cursor = resizeCursors[handle] { return cursor }
            let cursor = makeResizeCursor(for: handle)
            resizeCursors[handle] = cursor
            return cursor
        }
    }

    private static func makeResizeCursor(for handle: Handle) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return legacyResizeCursor(for: handle)
    }

    /// The resize cursors for macOS 14, which has no public diagonal arrows: the corners get an
    /// arrow that this app draws.
    static func legacyResizeCursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return diagonalCursor(fallsToTheRight: true)
        case .topRight, .bottomLeft: return diagonalCursor(fallsToTheRight: false)
        }
    }

    /// A diagonal arrow with two heads, black with a white edge.
    private static func diagonalCursor(fallsToTheRight: Bool) -> NSCursor {
        let side: CGFloat = 18
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { _ in
            let arrow = NSBezierPath()
            let low: CGFloat = 3, high = side - 3, head: CGFloat = 5
            // From the top-left to the bottom-right. The other diagonal is its mirror image.
            arrow.move(to: CGPoint(x: low, y: high))
            arrow.line(to: CGPoint(x: high, y: low))
            arrow.move(to: CGPoint(x: low + head, y: high))
            arrow.line(to: CGPoint(x: low, y: high))
            arrow.line(to: CGPoint(x: low, y: high - head))
            arrow.move(to: CGPoint(x: high - head, y: low))
            arrow.line(to: CGPoint(x: high, y: low))
            arrow.line(to: CGPoint(x: high, y: low + head))
            if !fallsToTheRight {
                var mirror = AffineTransform(translationByX: side, byY: 0)
                mirror.scale(x: -1, y: 1)
                arrow.transform(using: mirror)
            }
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            NSColor.white.setStroke()
            arrow.lineWidth = 4
            arrow.stroke()
            NSColor.black.setStroke()
            arrow.lineWidth = 1.5
            arrow.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: side / 2, y: side / 2))
    }
}
