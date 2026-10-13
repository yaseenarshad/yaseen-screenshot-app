import CoreGraphics
import Foundation

/// The keys that a capture understands. The view maps key codes to these.
public enum CaptureKey {
    case enter
    case escape
    /// Command-Z.
    case undo
    /// Shift-Command-Z.
    case redo
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

/// What a drag from a point does. The view shows a pointer shape for each case.
public enum PointerShape: Equatable {
    /// A drag makes a box or draws a mark.
    case crosshair
    /// A drag moves the box.
    case openHand
    /// The box moves now.
    case closedHand
    /// A drag changes the size of the box.
    case resize(Handle)
    /// A click puts a text.
    case iBeam
    /// A drag does nothing.
    case arrow
}

/// A text that the user types now. It is not a mark yet.
public struct TextEdit: Equatable {
    /// The top-left of the text, in the points of the box.
    public var origin: CGPoint
    /// A line breaks at this width: the right edge of the box.
    public var wrapWidth: CGFloat
    public var style: MarkStyle
    public var text: String
}

/// The state of one capture, with no window and no view.
///
/// One instance serves all screens, because only one box exists at a time.
/// The view is a thin adapter: it turns `NSEvent`s into these calls and draws what it reads here.
/// Every point is in the points of its screen, with the origin at the top-left of that screen.
/// The points of a mark are in the points of the box.
public final class CaptureInteraction {
    /// A pointer that moved less than this is a click, not a drag.
    public static let minimumDrag: CGFloat = 3

    public let displays: [FrozenDisplay]
    public private(set) var marks = MarkList()
    /// The selected tool. With no tool, a drag changes the box.
    public private(set) var tool: Tool?
    /// The text that is open, if the user types one now.
    public private(set) var textEdit: TextEdit?
    /// Goes up each time the visible marks change. The view makes its marks image again only then.
    public private(set) var marksRevision = 0

    /// Called after something that the views show changed. The views draw again.
    public var onChange: (() -> Void)?
    /// Called one time, when the capture ends.
    public var onFinish: ((CaptureOutcome) -> Void)?

    private enum Drag {
        case newBox(display: FrozenDisplay, start: CGPoint)
        case move(display: FrozenDisplay, original: Selection, start: CGPoint)
        /// `offset` is from the handle to the pointer, so the edge does not jump to the pointer.
        case resize(display: FrozenDisplay, original: Selection, handle: Handle, start: CGPoint, offset: CGPoint)
        case draw(tool: Tool, style: MarkStyle, start: CGPoint)
    }

    /// The windows that a click can select: for each screen, their frames from the front to the back.
    private var windows: [CGDirectDisplayID: [CGRect]]
    private let styles: ToolStyleMemory
    private var box: (display: FrozenDisplay, selection: Selection)?
    private var drag: Drag?
    /// False until the pointer of the current drag moved `minimumDrag` points.
    private var dragIsPastMinimum = false
    /// The mark of the drag that draws now.
    private var draft: Mark?
    /// The last place of the pointer, for the window that is bright before a box exists.
    private var hover: (displayID: CGDirectDisplayID, point: CGPoint)?
    private var isFinished = false

    public init(
        displays: [FrozenDisplay],
        windows: [CGDirectDisplayID: [CGRect]] = [:],
        styles: ToolStyleMemory = .shared
    ) {
        self.displays = displays
        self.windows = windows
        self.styles = styles
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

    /// The frame of the window below the pointer, on the screen that has the pointer.
    /// A click selects it. It shows only while no box exists.
    public func highlight(on displayID: CGDirectDisplayID) -> CGRect? {
        guard !isFinished, box == nil, let hover = hover, hover.displayID == displayID else { return nil }
        return WindowSnap.topFrame(in: windows[displayID] ?? [], at: hover.point)
    }

    /// The box has its handles when it is free to change: no mark holds it, no text is open,
    /// and the pointer of the first drag is released.
    public var showsHandles: Bool {
        box != nil && marks.isEmpty && textEdit == nil && !isMakingBox
    }

    /// The toolbar shows on the screen of the box, after the pointer of the first drag is released.
    public func showsToolbar(on displayID: CGDirectDisplayID) -> Bool {
        selection(on: displayID) != nil && !isMakingBox
    }

    /// The colour and the size that the next mark of the selected tool gets.
    public var style: MarkStyle? {
        tool.map { styles[$0] }
    }

    /// The marks to draw: the marks of the list, and the mark of the drag that draws now.
    public var visibleMarks: [Mark] {
        draft.map { marks.marks + [$0] } ?? marks.marks
    }

    public var canUndo: Bool {
        marks.canUndo || textEdit != nil
    }

    /// What a drag from `point` does, for the shape of the pointer.
    public func pointerShape(at point: CGPoint, on displayID: CGDirectDisplayID) -> PointerShape {
        switch drag {
        case .move?: return .closedHand
        case .resize(_, _, let handle, _, _)?: return .resize(handle)
        default: break
        }
        // The box is held when marks exist, and when a tool is selected.
        let boxIsHeld = tool != nil || !marks.isEmpty || textEdit != nil
        guard let selection = selection(on: displayID) else {
            return boxIsHeld ? .arrow : .crosshair
        }
        if showsHandles, case .handle(let handle)? = selection.part(at: point) {
            return .resize(handle)
        }
        if let tool = tool {
            guard selection.contains(point) else { return .arrow }
            return tool == .text ? .iBeam : .crosshair
        }
        guard !boxIsHeld else { return .arrow }
        return selection.contains(point) ? .openHand : .crosshair
    }

    // MARK: The pointer

    /// Gives the window list after the capture started. The overlay shows first, because the
    /// first read of the list in the life of the app is slow.
    public func setWindows(_ frames: [CGDirectDisplayID: [CGRect]]) {
        guard !isFinished else { return }
        let before = hover.flatMap { highlight(on: $0.displayID) }
        windows = frames
        if hover.flatMap({ highlight(on: $0.displayID) }) != before {
            onChange?()
        }
    }

    /// The pointer moved with no button down.
    public func pointerMoved(to point: CGPoint, on displayID: CGDirectDisplayID) {
        guard !isFinished else { return }
        let before = hover.flatMap { highlight(on: $0.displayID) }
        let screenBefore = hover?.displayID
        hover = (displayID, point)
        // Only a change of the bright window draws again, not each move.
        if highlight(on: displayID) != before || (before != nil && screenBefore != displayID) {
            onChange?()
        }
    }

    public func pointerDown(at point: CGPoint, on displayID: CGDirectDisplayID) {
        drag = nil
        dragIsPastMinimum = false
        guard !isFinished, let display = displays.first(where: { $0.displayID == displayID }) else { return }
        hover = (displayID, point)
        // A click in a different place completes the text that is open.
        completeText()

        let selection = self.selection(on: displayID)
        if showsHandles, let selection = selection, case .handle(let handle)? = selection.part(at: point) {
            let middle = selection.handlePoint(handle)
            let offset = CGPoint(x: point.x - middle.x, y: point.y - middle.y)
            drag = .resize(display: display, original: selection, handle: handle, start: point, offset: offset)
            return
        }
        if let tool = tool {
            // With a tool, a drag in the box draws. A drag that starts outside the box does nothing.
            guard let selection = selection, selection.contains(point) else { return }
            if tool == .text {
                beginText(at: point, in: selection)
            } else {
                drag = .draw(tool: tool, style: styles[tool], start: point)
            }
            return
        }
        // With marks, the box is fixed, and no drag makes a new box. This protects the marks.
        guard marks.isEmpty else { return }
        if let selection = selection, selection.contains(point) {
            drag = .move(display: display, original: selection, start: point)
        } else {
            drag = .newBox(display: display, start: point)
        }
    }

    public func pointerDragged(to point: CGPoint) {
        guard !isFinished, let drag = drag else { return }
        let start: CGPoint
        switch drag {
        case .newBox(_, let from), .move(_, _, let from), .resize(_, _, _, let from, _), .draw(_, _, let from):
            start = from
        }
        if !dragIsPastMinimum {
            guard hypot(point.x - start.x, point.y - start.y) >= CaptureInteraction.minimumDrag else { return }
            dragIsPastMinimum = true
        }

        switch drag {
        case .newBox(let display, _):
            // The box stays on the screen of the pointer down, also when the pointer leaves that screen.
            setBox(Selection(from: start, to: point, in: display.frame.size), on: display)
        case .move(let display, let original, _):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            setBox(original.moved(by: delta, in: display.frame.size), on: display)
        case .resize(let display, let original, let handle, _, let offset):
            let edge = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
            setBox(original.resized(handle, to: edge, in: display.frame.size), on: display)
        case .draw(let tool, let style, _):
            extendDraft(tool: tool, style: style, from: start, to: point)
        }
    }

    public func pointerUp(at point: CGPoint) {
        pointerDragged(to: point)
        guard !isFinished, let drag = drag else { return }
        let wasDrag = dragIsPastMinimum
        self.drag = nil
        dragIsPastMinimum = false

        switch drag {
        case .newBox(let display, let start):
            if wasDrag {
                // The pointer is released: the handles and the toolbar show.
                onChange?()
            } else if box == nil,
                      let frame = WindowSnap.topFrame(in: windows[display.displayID] ?? [], at: start),
                      let selection = Selection(rect: frame, in: display.frame.size) {
                // A click on the bright window: the box is that window.
                setBox(selection, on: display)
            }
        case .draw:
            if let mark = draft {
                draft = nil
                marks.add(mark)
                marksChanged()
            }
        case .move, .resize:
            break
        }
    }

    public func doubleClick(at point: CGPoint, on displayID: CGDirectDisplayID) {
        // With a tool selected, a double-click draws. Only Enter and the Done button mean Done.
        guard tool == nil, selection(on: displayID)?.contains(point) == true else { return }
        done()
    }

    /// A right-click: it removes the box, or cancels when no box exists.
    /// With marks or an open text it does nothing, so the work is not lost.
    public func secondaryClick() {
        guard !isFinished else { return }
        guard marks.isEmpty, textEdit == nil else { return }
        drag = nil
        dragIsPastMinimum = false
        if draft != nil {
            // During a drag that draws, a right-click removes only the mark of that drag.
            draft = nil
            marksChanged()
            return
        }
        if box == nil {
            finish(.cancel)
        } else {
            box = nil
            tool = nil
            marks.clearRedo()
            onChange?()
        }
    }

    // MARK: The keys and the toolbar

    public func key(_ key: CaptureKey) {
        switch key {
        case .enter:
            done()
        case .escape:
            // Esc removes the text that is not complete, and the capture stays open.
            if textEdit != nil, !isFinished {
                textEdit = nil
                onChange?()
            } else {
                cancel()
            }
        case .undo:
            undo()
        case .redo:
            redo()
        }
    }

    /// Enter and the Done button. A text that is open is completed first.
    public func done() {
        guard !isFinished else { return }
        completeText()
        guard let box = box else { return }
        finish(.done(CaptureResult(display: box.display, selection: box.selection, marks: marks)))
    }

    public func cancel() {
        finish(.cancel)
    }

    /// A click on a tool selects it. A click on the selected tool clears the selection.
    public func selectTool(_ newTool: Tool) {
        guard !isFinished, box != nil else { return }
        completeText()
        tool = tool == newTool ? nil : newTool
        onChange?()
    }

    /// The colour of the next mark of the selected tool. A mark that exists does not change.
    public func setColor(_ color: MarkColor) {
        guard !isFinished, let tool = tool else { return }
        styles[tool].color = color
        // A text that is open is not a mark yet, so it gets the new colour.
        textEdit?.style = styles[tool]
        onChange?()
    }

    public func setSize(_ size: MarkSize) {
        guard !isFinished, let tool = tool else { return }
        styles[tool].size = size
        textEdit?.style = styles[tool]
        onChange?()
    }

    /// Removes the last mark. A text that is open is completed first, and then it is the last mark.
    public func undo() {
        guard !isFinished else { return }
        completeText()
        if marks.undo() { marksChanged() }
    }

    public func redo() {
        guard !isFinished else { return }
        completeText()
        if marks.redo() { marksChanged() }
    }

    // MARK: Text

    /// The text field tells what the user typed.
    public func textChanged(_ text: String) {
        textEdit?.text = text
    }

    /// Return, or a click in a different place: the open text becomes a mark. An empty text adds no mark.
    public func completeText() {
        guard !isFinished, let edit = textEdit else { return }
        textEdit = nil
        if !edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            marks.add(Mark(tool: .text, style: edit.style, points: [edit.origin], text: edit.text, wrapWidth: edit.wrapWidth))
            marksRevision += 1
        }
        onChange?()
    }

    private func beginText(at point: CGPoint, in selection: Selection) {
        let style = styles[.text]
        let size = selection.rect.size
        // The click is the middle of the first line. Near the right or the bottom edge, the text
        // moves into the box, so the field does not leave the box.
        let lineHeight = (style.fontSize * 1.25).rounded(.up)
        let x = max(min(point.x - selection.rect.minX, size.width - 2 * style.fontSize), 0).rounded()
        let y = max(min(point.y - selection.rect.minY - lineHeight / 2, size.height - lineHeight), 0).rounded()
        textEdit = TextEdit(origin: CGPoint(x: x, y: y), wrapWidth: size.width - x, style: style, text: "")
        onChange?()
    }

    // MARK: Changes

    private var isMakingBox: Bool {
        if case .newBox? = drag { return dragIsPastMinimum }
        return false
    }

    private func setBox(_ selection: Selection, on display: FrozenDisplay) {
        guard box?.display.displayID != display.displayID || box?.selection != selection else { return }
        box = (display, selection)
        // The marks that Undo removed belong to the old box.
        marks.clearRedo()
        onChange?()
    }

    private func marksChanged() {
        marksRevision += 1
        onChange?()
    }

    /// The mark of a drag that draws. Its points stop inside the box: half a line width before
    /// the edge, so the full line is visible.
    private func extendDraft(tool: Tool, style: MarkStyle, from start: CGPoint, to point: CGPoint) {
        guard let selection = box?.selection else { return }
        let inset = style.lineWidth(for: tool) / 2
        func inBox(_ screenPoint: CGPoint) -> CGPoint {
            CGPoint(
                x: CaptureInteraction.clamp(screenPoint.x - selection.rect.minX, inset: inset, length: selection.rect.width),
                y: CaptureInteraction.clamp(screenPoint.y - selection.rect.minY, inset: inset, length: selection.rect.height)
            )
        }
        var mark = draft ?? Mark(tool: tool, style: style, points: [inBox(start)])
        let next = inBox(point)
        switch tool {
        case .pen, .highlight:
            guard mark.points.last != next else { return }
            mark.points.append(next)
        default:
            guard mark.points.count < 2 || mark.points[1] != next else { return }
            mark.points = [mark.points[0], next]
        }
        draft = mark
        marksChanged()
    }

    private static func clamp(_ value: CGFloat, inset: CGFloat, length: CGFloat) -> CGFloat {
        // A box that is narrower than the line keeps the point in its middle.
        let low = min(inset, length / 2)
        return min(max(value, low), length - low)
    }

    // MARK: The end

    private func finish(_ outcome: CaptureOutcome) {
        guard !isFinished else { return }
        isFinished = true
        drag = nil
        draft = nil
        textEdit = nil
        onFinish?(outcome)
    }
}
