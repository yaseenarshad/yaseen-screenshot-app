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

    /// The style of a tool before the user changed it.
    public static func initial(for tool: Tool) -> MarkStyle {
        MarkStyle(color: tool == .highlight ? .amber : .red, size: .medium)
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
}

/// One mark. Its points are in the points of the box: the top-left of the box is 0, 0.
public struct Mark: Equatable {
    public let tool: Tool
    public var style: MarkStyle
    /// Rectangle, Ellipse and Arrow: the start and the end of the drag.
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

/// The marks of one capture, with Undo and Redo.
public struct MarkList: Equatable {
    public private(set) var marks: [Mark] = []
    private var undone: [Mark] = []

    public init() {}

    public var isEmpty: Bool { marks.isEmpty }
    public var canUndo: Bool { !marks.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    /// A new mark. Redo can no longer bring back the marks that Undo removed.
    public mutating func add(_ mark: Mark) {
        marks.append(mark)
        undone = []
    }

    /// Removes the last mark. Returns `false` when no mark exists.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = marks.popLast() else { return false }
        undone.append(last)
        return true
    }

    /// Puts back the mark that the last Undo removed. Returns `false` when there is none.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let last = undone.popLast() else { return false }
        marks.append(last)
        return true
    }

    public mutating func clearRedo() {
        undone = []
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
