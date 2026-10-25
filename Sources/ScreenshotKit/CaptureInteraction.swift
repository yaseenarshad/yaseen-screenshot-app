import CoreGraphics
import Foundation

/// The keys that a capture understands. The view maps key codes to these. `AppController` sends the hotkey.
public enum CaptureKey {
    case enter
    /// The hotkey, pressed again during the capture. It does the same as Enter.
    case hotKey
    case escape
    /// Command-Z.
    case undo
    /// Shift-Command-Z.
    case redo
    /// Delete or Backspace.
    case delete
    /// Command-C, Command-X and Command-V: the selected mark (YAZ-3148).
    case copy, cut, paste
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
    /// A drag makes a box, draws a mark, or moves an end of an Arrow.
    case crosshair
    /// A drag moves the box, or the mark below the pointer.
    case openHand
    /// The box or a mark moves now.
    case closedHand
    /// A drag changes the size of the box, or of the selected mark.
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
    /// The place in the marks of the Text mark that is open again. `nil` for a new text.
    public var index: Int?
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
    /// The hotkey that finishes this capture, for the tip of Done. `nil` when macOS refused it.
    public let hotKey: HotKeyCombo?
    /// The keys of the toolbar. The toolbar shows them, and `toolbarKey` reads them.
    public let toolbarKeys: ToolbarKeys
    /// The tool that turns on when a box appears where no box was (D3, YAZ-2879). `nil` is "None".
    public let startTool: Tool?
    public private(set) var marks = MarkList()
    /// The selected tool. With no tool, a drag in the box moves it. With a tool, it draws.
    public private(set) var tool: Tool?
    /// True while "Select" is selected in the toolbar. Then a click selects a mark, and no tool
    /// draws. It is not a `Tool`, because a `Tool` is also the kind of a mark.
    public private(set) var isSelecting = false
    /// The place of the selected mark in `marks`.
    public private(set) var selectedIndex: Int?
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
        case moveMark(index: Int, original: Mark, start: CGPoint)
        /// `offset` is from the handle to the pointer, as for the box.
        case resizeMark(index: Int, original: Mark, handle: MarkHandle, start: CGPoint, offset: CGPoint)
    }

    /// The windows that a click can select: for each screen, their frames from the front to the back.
    private var windows: [CGDirectDisplayID: [CGRect]]
    private let styles: ToolStyleMemory
    /// Where Command-C puts a mark. The app has one, so a mark can go into the next capture.
    private let clipboard: MarkClipboard
    private var box: (display: FrozenDisplay, selection: Selection)?
    private var drag: Drag?
    /// False until the pointer of the current drag moved `minimumDrag` points.
    private var dragIsPastMinimum = false
    /// The mark of the drag that draws or changes a mark now. `index` is the place of the mark
    /// that changes, or `nil` for a new mark. The list of marks changes one time, at the release:
    /// thus one drag is one Undo step.
    private var draft: (mark: Mark, index: Int?)?
    /// The last place of the pointer, for the window that is bright before a box exists.
    private var hover: (displayID: CGDirectDisplayID, point: CGPoint)?
    private var isFinished = false

    public init(
        displays: [FrozenDisplay],
        windows: [CGDirectDisplayID: [CGRect]] = [:],
        hotKey: HotKeyCombo? = nil,
        toolbarKeys: ToolbarKeys = ToolbarKeys(defaults: .standard),
        startTool: Tool? = nil,
        styles: ToolStyleMemory = .shared,
        clipboard: MarkClipboard = .shared
    ) {
        self.displays = displays
        self.windows = windows
        self.hotKey = hotKey
        self.toolbarKeys = toolbarKeys
        self.startTool = startTool
        self.styles = styles
        self.clipboard = clipboard
    }

    // MARK: What the views read

    /// The box on the given screen, or `nil` when the box is on a different screen or does not exist.
    public func selection(on displayID: CGDirectDisplayID) -> Selection? {
        box?.display.displayID == displayID ? box?.selection : nil
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

    /// The colour and the size that the toolbar shows: of the open text, else of the selected
    /// mark, else of the next mark of the selected tool. `nil` hides them.
    public var style: MarkStyle? {
        if let edit = textEdit { return edit.style }
        if let index = selectedIndex { return marks.marks[index].style }
        return tool.map { styles[$0] }
    }

    /// The marks to draw: the marks of the list, with the mark of the drag that draws or changes now.
    public var visibleMarks: [Mark] {
        var visible = marks.marks
        if let draft = draft {
            if let index = draft.index { visible[index] = draft.mark } else { visible.append(draft.mark) }
        }
        // A text that is open again shows in its field, not in the image.
        if let index = textEdit?.index { visible.remove(at: index) }
        return visible
    }

    /// The selected mark as it shows now: during a drag, the mark of the drag. The overlay draws
    /// its outline and its handles. The saved image never has them.
    public var selectedMark: Mark? {
        guard textEdit == nil, let index = selectedIndex else { return nil }
        if let draft = draft, draft.index == index { return draft.mark }
        return marks.marks[index]
    }

    public var canUndo: Bool {
        marks.canUndo || textEdit != nil
    }

    /// What a drag from `point` does, for the shape of the pointer.
    public func pointerShape(at point: CGPoint, on displayID: CGDirectDisplayID) -> PointerShape {
        switch drag {
        case .move?, .moveMark?: return .closedHand
        case .resize(_, _, let handle, _, _)?: return .resize(handle)
        case .resizeMark(_, _, let handle, _, _)?: return CaptureInteraction.pointerShape(for: handle)
        default: break
        }
        // The box is held when marks exist, or while a text is open.
        let boxIsHeld = !marks.isEmpty || textEdit != nil
        guard let selection = selection(on: displayID) else {
            return boxIsHeld ? .arrow : .crosshair
        }
        if showsHandles, case .handle(let handle)? = selection.part(at: point) {
            return .resize(handle)
        }
        if let tool = tool {
            // Outside the box, a drag makes a new box while no mark exists (D2, YAZ-2879).
            guard selection.contains(point) else { return boxIsHeld ? .arrow : .crosshair }
            return tool == .text ? .iBeam : .crosshair
        }
        if isSelecting, !marks.isEmpty {
            let inBox = CGPoint(x: point.x - selection.rect.minX, y: point.y - selection.rect.minY)
            if let handle = selectedMark?.handle(at: inBox) {
                return CaptureInteraction.pointerShape(for: handle.key)
            }
            return marks.index(at: inBox) != nil ? .openHand : .arrow
        }
        guard !boxIsHeld else { return .arrow }
        return selection.contains(point) ? .openHand : .crosshair
    }

    private static func pointerShape(for handle: MarkHandle) -> PointerShape {
        switch handle {
        case .frame(let handle): return .resize(handle)
        case .end: return .crosshair
        }
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
            // With a tool, a drag in the box draws. A drag that starts outside the box makes a new
            // box while no mark exists (D2, YAZ-2879), as with no tool. With marks it does nothing.
            guard let selection = selection, selection.contains(point) else {
                if marks.isEmpty { drag = .newBox(display: display, start: point) }
                return
            }
            if tool == .text {
                beginText(at: point, in: selection)
            } else if tool == .number {
                addNumber(at: point, in: selection)
            } else {
                drag = .draw(tool: tool, style: styles[tool], start: point)
            }
            return
        }
        // With marks, the box is fixed, and no drag makes a new box. This protects the marks.
        // With "Select", the pointer takes a mark. With no mark, "Select" changes the box as no tool does.
        guard marks.isEmpty else {
            if isSelecting, let selection = selection {
                takeMark(at: CGPoint(x: point.x - selection.rect.minX, y: point.y - selection.rect.minY), start: point)
            }
            return
        }
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
        case .newBox(_, let from), .move(_, _, let from), .resize(_, _, _, let from, _), .draw(_, _, let from),
             .moveMark(_, _, let from), .resizeMark(_, _, _, let from, _):
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
        case .moveMark(let index, let original, _):
            guard let boxRect = box?.selection.rect else { return }
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            setDraft(original.moved(by: delta, in: boxRect.size), at: index)
        case .resizeMark(let index, let original, let handle, _, let offset):
            guard let boxRect = box?.selection.rect else { return }
            // The place for the handle, in the points of the box.
            let target = CGPoint(x: point.x - boxRect.minX - offset.x, y: point.y - boxRect.minY - offset.y)
            setDraft(original.resized(handle, to: target, in: boxRect.size), at: index)
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
        case .draw, .moveMark, .resizeMark:
            // The release puts the mark of the drag in the list: one Undo step for one drag.
            if let draft = draft {
                self.draft = nil
                if let index = draft.index {
                    marks.replace(at: index, with: draft.mark)
                } else {
                    marks.add(draft.mark)
                }
                // A corner drag of a text sets the font of the next text too, as a digit does (YAZ-3318).
                if case .resizeMark = drag, draft.mark.tool == .text { styles[.text] = draft.mark.style }
                marksChanged()
            }
        case .move, .resize:
            break
        }
    }

    public func doubleClick(at point: CGPoint, on displayID: CGDirectDisplayID) {
        guard !isFinished, let selection = selection(on: displayID) else { return }
        if isSelecting {
            // A double-click on a Text mark opens its text again.
            completeText()
            let inBox = CGPoint(x: point.x - selection.rect.minX, y: point.y - selection.rect.minY)
            if let index = marks.index(at: inBox), marks.marks[index].tool == .text {
                openText(at: index)
            }
            return
        }
        // A double-click means Done with no tool, and with a tool that draws by a drag (D4, YAZ-2879):
        // its two clicks draw nothing. With Text or Number, a click puts a mark, so it is not Done.
        guard tool != .text, tool != .number, selection.contains(point) else { return }
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
            isSelecting = false
            marks.clearHistory()
            onChange?()
        }
    }

    // MARK: The keys and the toolbar

    public func key(_ key: CaptureKey) {
        switch key {
        case .enter, .hotKey:
            done()
        case .escape:
            // Esc removes the text that is not complete, and then it clears the selected mark.
            // The capture stays open. With neither, Esc cancels the capture.
            if let edit = textEdit, !isFinished {
                textEdit = nil
                // A text that was open again keeps its old text, and it shows in the image again.
                if edit.index != nil { marksRevision += 1 }
                onChange?()
            } else if selectedIndex != nil, !isFinished {
                selectedIndex = nil
                onChange?()
            } else {
                cancel()
            }
        case .undo:
            undo()
        case .redo:
            redo()
        case .delete:
            deleteSelectedMark()
        case .copy:
            copySelectedMark()
        case .cut:
            cutSelectedMark()
        case .paste:
            paste()
        }
    }

    /// Enter, the hotkey and the Done button. A text that is open is completed first.
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
        isSelecting = false
        releaseMark()
        onChange?()
    }

    /// A toolbar key (D2, YAZ-2872): it does the same as a click on its button, with one difference.
    /// A tool key always selects its tool. A second press does not clear it, so the next drag
    /// never moves the box by mistake.
    ///
    /// A key with no box or during a drag does nothing: the mark in progress keeps its tool and
    /// its style. While a text is open, the text field has the keyboard and each key is for the typing.
    public func toolbarKey(_ key: String) {
        guard !isFinished, box != nil, drag == nil, textEdit == nil else { return }
        // With a Text mark selected, a digit sets its font (YAZ-3318). It wins over the size or the
        // colour of that digit. A different mark keeps the keys of D4 (YAZ-2873).
        if selectedMark?.tool == .text, let fontSize = MarkStyle.digitFontSizes[key] {
            restyle { $0.fontSize = fontSize }
            return
        }
        guard let action = toolbarKeys.action(for: key) else { return }
        switch action {
        case .select:
            if !isSelecting { toggleSelecting() }
        case .tool(let newTool):
            if tool != newTool { selectTool(newTool) }
        case .size(let size):
            setSize(size)
        case .color(let color):
            setColor(color)
        }
    }

    /// A click on "Select" in the toolbar. A second click clears it, as for a tool.
    public func toggleSelecting() {
        guard !isFinished, box != nil else { return }
        completeText()
        isSelecting.toggle()
        tool = nil
        releaseMark()
        onChange?()
    }

    /// The colour of the selected mark, and of the next mark of that kind. With a tool, the
    /// colour of the next mark of the tool: a mark that exists and is not selected does not change.
    public func setColor(_ color: MarkColor) {
        restyle { $0.color = color }
    }

    /// The size of the line, or of the font of a text. The same targets as `setColor`.
    public func setSize(_ size: MarkSize) {
        restyle { $0.size = size }
    }

    private func restyle(_ change: (inout MarkStyle) -> Void) {
        guard !isFinished else { return }
        if var edit = textEdit {
            // A text that is open is not complete yet, so it gets the new style.
            change(&edit.style)
            change(&styles[.text])
            textEdit = edit
        } else if let index = selectedIndex, let size = box?.selection.rect.size {
            var mark = marks.marks[index]
            change(&mark.style)
            change(&styles[mark.tool])
            // A thicker line or a larger font can reach past an edge. The mark stays in the box.
            if marks.replace(at: index, with: mark.moved(by: .zero, in: size)) { marksRevision += 1 }
        } else if let tool = tool {
            change(&styles[tool])
        } else {
            return
        }
        onChange?()
    }

    /// Takes back the last change of the marks: a new mark, a move, a size change, a style change
    /// or a delete. A text that is open is completed first, and then it is the last change.
    public func undo() {
        guard !isFinished else { return }
        completeText()
        guard marks.undo() else { return }
        releaseMark()
        marksChanged()
    }

    public func redo() {
        guard !isFinished else { return }
        completeText()
        guard marks.redo() else { return }
        releaseMark()
        marksChanged()
    }

    /// Delete or Backspace: removes the selected mark.
    public func deleteSelectedMark() {
        guard !isFinished else { return }
        completeText()
        guard let index = selectedIndex else { return }
        releaseMark()
        marks.remove(at: index)
        marksChanged()
    }

    /// Command-C: the selected mark goes to the clipboard of marks. The marks do not change.
    public func copySelectedMark() {
        guard !isFinished, drag == nil, let mark = selectedMark else { return }
        clipboard.copy(mark)
    }

    /// Command-X: a copy, then a delete. It is one Undo step: the delete.
    public func cutSelectedMark() {
        guard !isFinished, drag == nil, let mark = selectedMark else { return }
        clipboard.cut(mark)
        deleteSelectedMark()
    }

    /// Command-V: a copy of the mark of the clipboard, above the other marks. One Undo step.
    public func paste() {
        guard !isFinished, drag == nil, textEdit == nil, let size = box?.selection.rect.size,
              let mark = clipboard.nextPaste(in: size) else { return }
        marks.add(mark)
        // The new mark is selected, with "Select", so a drag moves it at once (D3).
        tool = nil
        isSelecting = true
        selectedIndex = marks.marks.count - 1
        marksChanged()
    }

    // MARK: The selected mark

    /// "Select": a pointer down takes a handle of the selected mark, else the mark at the point.
    /// A drag then changes that mark. A pointer down on an empty place clears the selection.
    /// `point` is in the points of the box, and `start` is the same place on the screen.
    private func takeMark(at point: CGPoint, start: CGPoint) {
        if let index = selectedIndex, let handle = marks.marks[index].handle(at: point) {
            let offset = CGPoint(x: point.x - handle.point.x, y: point.y - handle.point.y)
            drag = .resizeMark(index: index, original: marks.marks[index], handle: handle.key, start: start, offset: offset)
            return
        }
        let index = marks.index(at: point)
        if let index = index {
            drag = .moveMark(index: index, original: marks.marks[index], start: start)
        }
        if index != selectedIndex {
            selectedIndex = index
            onChange?()
        }
    }

    /// Clears the selection, and ends a drag of a mark. The selection is a place in the list of
    /// marks, so it is not correct after Undo, Redo or a delete changed that list.
    private func releaseMark() {
        selectedIndex = nil
        switch drag {
        case .moveMark?, .resizeMark?:
            drag = nil
            draft = nil
        default:
            break
        }
    }

    private func setDraft(_ mark: Mark, at index: Int) {
        guard draft?.mark != mark else { return }
        draft = (mark, index)
        marksChanged()
    }

    // MARK: Text

    /// The text field tells what the user typed.
    public func textChanged(_ text: String) {
        textEdit?.text = text
    }

    /// Return, or a click in a different place: the open text becomes a mark. An empty text adds
    /// no mark. For a text that was open again, the mark changes, and an empty text removes it.
    public func completeText() {
        guard !isFinished, let edit = textEdit else { return }
        textEdit = nil
        let mark = Mark(tool: .text, style: edit.style, points: [edit.origin], text: edit.text, wrapWidth: edit.wrapWidth)
        let isEmpty = edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let index = edit.index {
            if isEmpty {
                selectedIndex = nil
                marks.remove(at: index)
            } else {
                marks.replace(at: index, with: mark)
            }
            // The mark shows in the image again.
            marksRevision += 1
        } else if !isEmpty {
            marks.add(mark)
            marksRevision += 1
        }
        onChange?()
    }

    /// Return: the open text becomes a mark, as `completeText` does. A new text is then the
    /// selected mark, with "Select" on (YAZ-3318). Thus a digit, a corner drag or a move works at
    /// once. T, or a click on Text, starts the next text.
    public func returnInText() {
        guard !isFinished, let edit = textEdit else { return }
        completeText()
        guard edit.index == nil, !edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        tool = nil
        isSelecting = true
        selectedIndex = marks.marks.count - 1
        onChange?()
    }

    /// Opens the text of a Text mark again, with its old text. The mark is the selected mark.
    private func openText(at index: Int) {
        let mark = marks.marks[index]
        guard let origin = mark.points.first else { return }
        // The second pointer down of the double-click started a drag of the mark. It ends here.
        drag = nil
        dragIsPastMinimum = false
        draft = nil
        selectedIndex = index
        textEdit = TextEdit(origin: origin, wrapWidth: mark.wrapWidth, style: mark.style, text: mark.text, index: index)
        // The text shows in its field now, not in the image.
        marksChanged()
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

    // MARK: Number

    /// A click with Number puts the next number at once, with its middle in the box. A drag
    /// after it does nothing more. One click is one Undo step.
    private func addNumber(at point: CGPoint, in selection: Selection) {
        let style = styles[.number]
        let inBox = CGPoint(x: point.x - selection.rect.minX, y: point.y - selection.rect.minY)
        let middle = style.pointInBox(inBox, for: .number, in: selection.rect.size)
        marks.add(Mark(tool: .number, style: style, points: [middle], number: marks.nextNumber))
        marksChanged()
    }

    // MARK: Changes

    private var isMakingBox: Bool {
        if case .newBox? = drag { return dragIsPastMinimum }
        return false
    }

    private func setBox(_ selection: Selection, on display: FrozenDisplay) {
        guard box?.display.displayID != display.displayID || box?.selection != selection else { return }
        // A box where no box was: the tool of the setting turns on (D3, YAZ-2879). A new box that
        // replaces a box keeps the tool that is on, also when the user turned it off.
        if box == nil { tool = startTool }
        box = (display, selection)
        // The box changes only while no mark exists. The marks of Undo and Redo belong to the old box.
        marks.clearHistory()
        onChange?()
    }

    private func marksChanged() {
        marksRevision += 1
        onChange?()
    }

    /// The mark of a drag that draws. Its points stop inside the box: half a line width before
    /// the edge, so the full line is visible.
    private func extendDraft(tool: Tool, style: MarkStyle, from start: CGPoint, to point: CGPoint) {
        guard let boxRect = box?.selection.rect else { return }
        func inBox(_ screenPoint: CGPoint) -> CGPoint {
            style.pointInBox(
                CGPoint(x: screenPoint.x - boxRect.minX, y: screenPoint.y - boxRect.minY), for: tool, in: boxRect.size
            )
        }
        var mark = draft?.mark ?? Mark(tool: tool, style: style, points: [inBox(start)])
        let next = inBox(point)
        switch tool {
        case .pen, .highlight:
            guard mark.points.last != next else { return }
            mark.points.append(next)
        default:
            guard mark.points.count < 2 || mark.points[1] != next else { return }
            mark.points = [mark.points[0], next]
        }
        draft = (mark, nil)
        marksChanged()
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
