import CoreGraphics

// The model of the marks that the user draws in the box. No drawing here: `MarkRenderer` draws.

/// The six tools, in the order of the toolbar.
public enum Tool: Hashable, CaseIterable {
    case rectangle, ellipse, arrow, pen, highlight, text

    public var name: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .pen: return "Pen"
        case .highlight: return "Highlight"
        case .text: return "Text"
        }
    }
}

public enum MarkSize: Hashable, CaseIterable {
    case thin, medium, thick

    public var name: String {
        switch self {
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }
}

public enum MarkColor: Hashable, CaseIterable {
    case red, amber, green, blue, black, white

    public var name: String {
        switch self {
        case .red: return "Red"
        case .amber: return "Amber"
        case .green: return "Green"
        case .blue: return "Blue"
        case .black: return "Black"
        case .white: return "White"
        }
    }

    /// The colour in sRGB, each part from 0 to 1.
    public var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: return (1.0, 0.23, 0.19)
        case .amber: return (1.0, 0.70, 0.0)
        case .green: return (0.20, 0.78, 0.35)
        case .blue: return (0.0, 0.48, 1.0)
        case .black: return (0, 0, 0)
        case .white: return (1, 1, 1)
        }
    }
}

/// The colour and the size of a mark.
public struct MarkStyle: Equatable {
    public var color: MarkColor
    public var size: MarkSize

    public init(color: MarkColor, size: MarkSize) {
        self.color = color
        self.size = size
    }

    /// The style of a tool before the user changed it: the thickest size (D15 on YAZ-2782).
    public static func initial(for tool: Tool) -> MarkStyle {
        MarkStyle(color: tool == .highlight ? .amber : .red, size: .thick)
    }

    /// The width of the line in points. Highlight is a wide line.
    public func lineWidth(for tool: Tool) -> CGFloat {
        switch (tool == .highlight, size) {
        case (false, .thin): return 2
        case (false, .medium): return 4
        case (false, .thick): return 7
        case (true, .thin): return 10
        case (true, .medium): return 16
        case (true, .thick): return 24
        }
    }

    /// The size of the font of a Text mark, in points.
    public var fontSize: CGFloat {
        switch size {
        case .thin: return 14
        case .medium: return 18
        case .thick: return 24
        }
    }

    /// A point of a mark, kept in a box of `size`: it stops half a line width before each edge,
    /// so the full line is visible.
    public func pointInBox(_ point: CGPoint, for tool: Tool, in size: CGSize) -> CGPoint {
        let inset = lineWidth(for: tool) / 2
        func clamp(_ value: CGFloat, _ length: CGFloat) -> CGFloat {
            // A box that is narrower than the line keeps the point in its middle.
            let low = min(inset, length / 2)
            return min(max(value, low), length - low)
        }
        return CGPoint(x: clamp(point.x, size.width), y: clamp(point.y, size.height))
    }
}

/// One mark. Its points are in the points of the box: the top-left of the box is 0, 0.
public struct Mark: Equatable {
    public let tool: Tool
    public var style: MarkStyle
    /// Rectangle and Ellipse: two opposite corners. Arrow: the start, and the end with the head.
    /// Pen and Highlight: the path of the pointer. Text: the top-left of the text.
    public var points: [CGPoint]
    /// Only for Text.
    public var text: String
    /// Only for Text: a line breaks at this width.
    public var wrapWidth: CGFloat

    public init(tool: Tool, style: MarkStyle, points: [CGPoint], text: String = "", wrapWidth: CGFloat = 0) {
        self.tool = tool
        self.style = style
        self.points = points
        self.text = text
        self.wrapWidth = wrapWidth
    }
}

/// A handle of the selected mark.
public enum MarkHandle: Hashable {
    /// Rectangle and Ellipse: one of the eight handles of the rectangle of the mark.
    case frame(Handle)
    /// Arrow: the start (0) or the end with the head (1).
    case end(Int)
}

/// The part of a mark that is below a point.
public enum MarkPart: Equatable {
    /// The line of the mark, or its text.
    case line
    /// The empty inside of a Rectangle or an Ellipse.
    case inside
}

// The geometry of a mark, for the Select tool (YAZ-2782): pure functions, with no view.
extension Mark {
    /// A click this near to the line of a mark selects the mark.
    public static let hitTolerance: CGFloat = 6
    /// The space between a mark and the outline that shows when it is selected.
    static let outlineGap: CGFloat = 3

    var lineWidth: CGFloat { style.lineWidth(for: tool) }

    /// The smallest rectangle around the points. For a Rectangle and an Ellipse, the middle of
    /// the line is on its edge.
    public var frame: CGRect {
        guard let first = points.first else { return .null }
        var low = first, high = first
        for point in points.dropFirst() {
            low = CGPoint(x: min(low.x, point.x), y: min(low.y, point.y))
            high = CGPoint(x: max(high.x, point.x), y: max(high.y, point.y))
        }
        return CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)
    }

    /// The area that the mark covers, with the width of its line.
    public var bounds: CGRect {
        let line = frame.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        switch tool {
        case .rectangle, .ellipse, .pen, .highlight:
            return line
        case .arrow:
            // The head is wider than the line.
            guard let head = arrowHead else { return line }
            let minX = min(line.minX, head.left.x, head.right.x), maxX = max(line.maxX, head.left.x, head.right.x)
            let minY = min(line.minY, head.left.y, head.right.y), maxY = max(line.maxY, head.left.y, head.right.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text:
            guard let origin = points.first else { return .null }
            return TextLayout(text: text, style: style, wrapWidth: wrapWidth).usedRect
                .offsetBy(dx: origin.x, dy: origin.y)
        }
    }

    /// The outline that the overlay shows around the selected mark.
    public var outline: CGRect {
        bounds.insetBy(dx: -Mark.outlineGap, dy: -Mark.outlineGap)
    }

    /// The head of an Arrow: its tip is the end of the drag, and `left` and `right` are the ends
    /// of its base. The head grows with the line width. `shaftEnd` is where the line stops, so
    /// the tip stays sharp. A short arrow is only a head, and then `shaftEnd` is `nil`.
    var arrowHead: (shaftEnd: CGPoint?, tip: CGPoint, left: CGPoint, right: CGPoint)? {
        guard tool == .arrow, let start = points.first, let end = points.last else { return nil }
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return nil }
        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let headLength = min(lineWidth * 3 + 6, length)
        let halfWidth = headLength * 0.45
        let base = CGPoint(x: end.x - direction.x * headLength, y: end.y - direction.y * headLength)
        return (
            length > headLength ? base : nil,
            end,
            CGPoint(x: base.x - direction.y * halfWidth, y: base.y + direction.x * halfWidth),
            CGPoint(x: base.x + direction.y * halfWidth, y: base.y - direction.x * halfWidth)
        )
    }

    // MARK: The hit test

    /// The part of the mark at `point`, or `nil` when the point is more than `tolerance` away
    /// from the mark. The empty inside of a Rectangle and of an Ellipse is a part too, so a
    /// click inside selects the mark.
    public func part(at point: CGPoint, tolerance: CGFloat = Mark.hitTolerance) -> MarkPart? {
        let reach = lineWidth / 2 + tolerance
        let frame = self.frame
        switch tool {
        case .rectangle:
            // How far the point is outside the rectangle of the line (below zero: inside).
            let outside = max(abs(point.x - frame.midX) - frame.width / 2, abs(point.y - frame.midY) - frame.height / 2)
            if outside > reach { return nil }
            return outside < -reach ? .inside : .line
        case .ellipse:
            /// True when the point is in the ellipse that is `extra` larger on each side.
            func isInEllipse(_ extra: CGFloat) -> Bool {
                let a = frame.width / 2 + extra, b = frame.height / 2 + extra
                guard a > 0, b > 0 else { return false }
                let x = (point.x - frame.midX) / a, y = (point.y - frame.midY) / b
                return x * x + y * y <= 1
            }
            guard isInEllipse(reach) else { return nil }
            return isInEllipse(-reach) ? .inside : .line
        case .arrow:
            if Mark.distance(from: point, toLineThrough: points) <= reach { return .line }
            guard let head = arrowHead else { return nil }
            return Mark.triangle(head.tip, head.left, head.right, contains: point) ? .line : nil
        case .pen, .highlight:
            return Mark.distance(from: point, toLineThrough: points) <= reach ? .line : nil
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) ? .line : nil
        }
    }

    /// The distance from `point` to the nearest point of the line through `points`.
    private static func distance(from point: CGPoint, toLineThrough points: [CGPoint]) -> CGFloat {
        guard var a = points.first else { return .infinity }
        var nearest = hypot(point.x - a.x, point.y - a.y)
        for b in points.dropFirst() {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            // How far along the segment from a to b the nearest point is, from 0 to 1.
            let along = lengthSquared > 0
                ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
                : 0
            nearest = min(nearest, hypot(point.x - a.x - along * dx, point.y - a.y - along * dy))
            a = b
        }
        return nearest
    }

    private static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, contains point: CGPoint) -> Bool {
        // The point is in the triangle when it is on the same side of all three edges.
        func side(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
            (to.x - from.x) * (point.y - from.y) - (to.y - from.y) * (point.x - from.x)
        }
        let sides = [side(a, b), side(b, c), side(c, a)]
        return sides.allSatisfy { $0 >= 0 } || sides.allSatisfy { $0 <= 0 }
    }

    // MARK: Handles, move and size change

    /// The handles of the selected mark, with their places: eight for a Rectangle and an Ellipse,
    /// and one at each end of an Arrow. A Pen, a Highlight and a Text mark only move.
    public var handles: [(key: MarkHandle, point: CGPoint)] {
        switch tool {
        case .rectangle, .ellipse:
            let frame = self.frame
            return Handle.allCases.map { (.frame($0), Selection.handlePoint($0, of: frame)) }
        case .arrow:
            return points.indices.map { (.end($0), points[$0]) }
        case .pen, .highlight, .text:
            return []
        }
    }

    /// The handle that a pointer down at `point` takes, with its place. The hit area of a handle
    /// is the hit area of a handle of the box.
    public func handle(at point: CGPoint) -> (key: MarkHandle, point: CGPoint)? {
        Selection.nearest(of: handles, to: point)
    }

    /// The mark moved by `delta`, in a box of `size`. The move stops when the bounds of the mark
    /// touch an edge of the box.
    public func moved(by delta: CGPoint, in size: CGSize) -> Mark {
        let bounds = self.bounds
        var room = CGPoint(x: size.width - bounds.maxX, y: size.height - bounds.maxY)
        if tool == .text {
            // A text stays on whole points, as a new text. Then the width for its lines (below)
            // is never less than the lines need, and the text has the same lines at the edge.
            room = CGPoint(x: room.x.rounded(.down), y: room.y.rounded(.down))
        }
        // Whole points, so a sharp line stays sharp. A mark that is larger than the box keeps
        // its top-left corner in the box.
        let dx = max(min(delta.x.rounded(), room.x), -bounds.minX)
        let dy = max(min(delta.y.rounded(), room.y), -bounds.minY)
        var moved = self
        moved.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        if tool == .text, let origin = moved.points.first {
            // A line of a text always breaks at the right edge of the box (YAZ-2767 row 22).
            moved.wrapWidth = size.width - origin.x
        }
        return moved
    }

    /// The mark after `handle` moved to `point`, in a box of `size`. A Rectangle and an Ellipse
    /// follow the rules of the box: the opposite edges stay, a handle that goes through the
    /// opposite edge turns the mark over, and the smallest side is `Selection.minimumSide`.
    /// An end of an Arrow moves, and its other end stays.
    public func resized(_ handle: MarkHandle, to point: CGPoint, in size: CGSize) -> Mark {
        var resized = self
        switch handle {
        case .frame(let handle):
            // The middle of the line stops half a line width before each edge of the box, as in
            // a drag that draws. Thus the area for the rectangle is smaller than the box: it
            // starts at `inset`, the nearest place to the corner 0, 0 of the box.
            let inset = style.pointInBox(.zero, for: tool, in: size)
            let area = CGSize(width: size.width - 2 * inset.x, height: size.height - 2 * inset.y)
            let whole = CGPoint(x: point.x.rounded() - inset.x, y: point.y.rounded() - inset.y)
            let rect = Selection.resized(frame.offsetBy(dx: -inset.x, dy: -inset.y), by: handle, to: whole, in: area)
                .offsetBy(dx: inset.x, dy: inset.y)
            resized.points = [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)]
        case .end(let index):
            guard points.count == 2, points.indices.contains(index) else { return self }
            let fixed = points[1 - index]
            var end = style.pointInBox(point, for: tool, in: size)
            let length = hypot(end.x - fixed.x, end.y - fixed.y)
            guard length > 0 else { return self }
            if length < Selection.minimumSide {
                // An arrow with no length draws nothing. The end stays this far from the other
                // end, in the direction of the pointer.
                let scale = Selection.minimumSide / length
                let far = CGPoint(x: fixed.x + (end.x - fixed.x) * scale, y: fixed.y + (end.y - fixed.y) * scale)
                end = style.pointInBox(far, for: tool, in: size)
            }
            resized.points[index] = end
        }
        return resized
    }
}

/// The marks of one capture, with Undo and Redo.
///
/// Undo keeps the list of marks from before each change. Thus one mechanism takes back a new
/// mark, a move, a size change, a style change and a delete.
public struct MarkList: Equatable {
    public private(set) var marks: [Mark] = []
    /// The lists from before each change, and the lists that Undo took back.
    private var undoStack: [[Mark]] = []
    private var redoStack: [[Mark]] = []

    public init() {}

    public var isEmpty: Bool { marks.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// A new mark, above the other marks.
    public mutating func add(_ mark: Mark) {
        change(to: marks + [mark])
    }

    /// The mark at `index` changes: a move, a size change or a new style. One call is one Undo
    /// step. Returns `false` when the mark is the same as before.
    @discardableResult
    public mutating func replace(at index: Int, with mark: Mark) -> Bool {
        guard marks.indices.contains(index), marks[index] != mark else { return false }
        var changed = marks
        changed[index] = mark
        change(to: changed)
        return true
    }

    public mutating func remove(at index: Int) {
        guard marks.indices.contains(index) else { return }
        var changed = marks
        changed.remove(at: index)
        change(to: changed)
    }

    /// A change. Redo can no longer bring back what Undo took back.
    private mutating func change(to changed: [Mark]) {
        undoStack.append(marks)
        redoStack = []
        marks = changed
    }

    /// Takes back the last change. Returns `false` when there is none.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let before = undoStack.popLast() else { return false }
        redoStack.append(marks)
        marks = before
        return true
    }

    /// Puts back the change that the last Undo took back. Returns `false` when there is none.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let after = redoStack.popLast() else { return false }
        undoStack.append(marks)
        marks = after
        return true
    }

    /// Forgets the changes. The box changed, and the marks of Undo and Redo belong to the old box.
    public mutating func clearHistory() {
        undoStack = []
        redoStack = []
    }

    /// The mark that a click at `point` selects, as its place in `marks`. The mark that was drawn
    /// last wins. A click on a line wins over a click in the empty inside of a Rectangle or an
    /// Ellipse. Thus a mark inside a larger mark can be selected.
    public func index(at point: CGPoint) -> Int? {
        var inside: Int?
        for index in marks.indices.reversed() {
            switch marks[index].part(at: point) {
            case .line?: return index
            case .inside?: inside = inside ?? index
            case nil: break
            }
        }
        return inside
    }
}

/// The colour and the size that each tool had last. It lives while the app runs; the app does not save it.
public final class ToolStyleMemory {
    /// The memory of the app. A capture uses it unless it gets its own (the tests do).
    public static let shared = ToolStyleMemory()

    private var styles: [Tool: MarkStyle] = [:]

    public init() {}

    public subscript(tool: Tool) -> MarkStyle {
        get { styles[tool] ?? .initial(for: tool) }
        set { styles[tool] = newValue }
    }
}
