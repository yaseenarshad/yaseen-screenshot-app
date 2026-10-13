import CoreGraphics

/// One of the eight handles on the border of the box.
public enum Handle: Hashable, CaseIterable {
    // The corners come first: a corner wins when two hit areas are equally near.
    case topLeft, topRight, bottomRight, bottomLeft
    case top, right, bottom, left

    /// The edge that this handle moves on the x axis: -1 the left edge, 1 the right edge, 0 none.
    var horizontal: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: return -1
        case .topRight, .right, .bottomRight: return 1
        case .top, .bottom: return 0
        }
    }

    /// The edge that this handle moves on the y axis: -1 the top edge, 1 the bottom edge, 0 none.
    var vertical: Int {
        switch self {
        case .topLeft, .top, .topRight: return -1
        case .bottomLeft, .bottom, .bottomRight: return 1
        case .left, .right: return 0
        }
    }
}

/// The part of the box that is below a point.
public enum SelectionPart: Equatable {
    case handle(Handle)
    case inside
}

/// The box of one capture: pure geometry.
///
/// The box is in the points of one screen. Its origin is the top-left of that screen.
/// It always uses whole points, so its edges are on whole pixels at scale 1 and at scale 2.
public struct Selection: Equatable {
    /// The smallest width and height of a box.
    public static let minimumSide: CGFloat = 4
    /// The side of the square around a handle that takes a pointer down. The visible handle is smaller.
    public static let handleHitSide: CGFloat = 12
    /// The space between the box and its label, and between the box and its toolbar.
    static let labelGap: CGFloat = 4
    static let toolbarGap: CGFloat = 8

    public private(set) var rect: CGRect

    /// The box between the two ends of a drag, in any direction.
    /// The box stays inside a screen of `screenSize` points.
    public init(from start: CGPoint, to end: CGPoint, in screenSize: CGSize) {
        let x = Selection.span(fixed: start.x.rounded(), moving: end.x.rounded(), limit: screenSize.width)
        let y = Selection.span(fixed: start.y.rounded(), moving: end.y.rounded(), limit: screenSize.height)
        rect = CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length)
    }

    /// The box on a rectangle that exists already (the frame of a window): cut to the screen,
    /// on whole points. `nil` when less than the smallest box is on the screen.
    public init?(rect: CGRect, in screenSize: CGSize) {
        let minX = min(max(rect.minX.rounded(), 0), screenSize.width)
        let maxX = min(max(rect.maxX.rounded(), 0), screenSize.width)
        let minY = min(max(rect.minY.rounded(), 0), screenSize.height)
        let maxY = min(max(rect.maxY.rounded(), 0), screenSize.height)
        guard maxX - minX >= Selection.minimumSide, maxY - minY >= Selection.minimumSide else { return nil }
        self.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func contains(_ point: CGPoint) -> Bool {
        rect.contains(point)
    }

    /// The box in the pixels of the frozen image (top-left origin) for a display of `scale`.
    public func pixelRect(scale: CGFloat) -> CGRect {
        CGRect(
            x: (rect.minX * scale).rounded(),
            y: (rect.minY * scale).rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
    }

    // MARK: Handles

    /// The middle of a handle: a corner of the box, or the middle of an edge.
    public func handlePoint(_ handle: Handle) -> CGPoint {
        Selection.handlePoint(handle, of: rect)
    }

    /// What a pointer down at `point` takes: the nearest handle, else the inside, else nothing.
    public func part(at point: CGPoint) -> SelectionPart? {
        let handles = Handle.allCases.map { (key: $0, point: handlePoint($0)) }
        if let nearest = Selection.nearest(of: handles, to: point) { return .handle(nearest.key) }
        return contains(point) ? .inside : nil
    }

    // The same geometry for any rectangle. The box uses it, and a Rectangle mark and an Ellipse
    // mark use it for their handles (YAZ-2782).

    /// The middle of a handle of `rect`: a corner, or the middle of an edge.
    static func handlePoint(_ handle: Handle, of rect: CGRect) -> CGPoint {
        CGPoint(
            x: handle.horizontal < 0 ? rect.minX : handle.horizontal > 0 ? rect.maxX : rect.midX,
            y: handle.vertical < 0 ? rect.minY : handle.vertical > 0 ? rect.maxY : rect.midY
        )
    }

    /// The handle that a pointer down at `point` takes: the nearest handle that has the point in
    /// its hit area. The first handle wins when two are equally near.
    static func nearest<Key>(of handles: [(key: Key, point: CGPoint)], to point: CGPoint) -> (key: Key, point: CGPoint)? {
        let reach = handleHitSide / 2
        var nearest: (handle: (key: Key, point: CGPoint), distance: CGFloat)?
        for handle in handles {
            let distance = max(abs(point.x - handle.point.x), abs(point.y - handle.point.y))
            if distance <= reach, distance < nearest?.distance ?? .infinity {
                nearest = (handle, distance)
            }
        }
        return nearest?.handle
    }

    /// `rect` after `handle` moved to `point`, inside an area of `size`. The opposite edges stay
    /// in place. A handle that goes through the opposite edge turns the rectangle over.
    static func resized(_ rect: CGRect, by handle: Handle, to point: CGPoint, in size: CGSize) -> CGRect {
        var resized = rect
        if handle.horizontal != 0 {
            let fixed = handle.horizontal < 0 ? rect.maxX : rect.minX
            let x = span(fixed: fixed, moving: point.x, limit: size.width)
            resized.origin.x = x.origin
            resized.size.width = x.length
        }
        if handle.vertical != 0 {
            let fixed = handle.vertical < 0 ? rect.maxY : rect.minY
            let y = span(fixed: fixed, moving: point.y, limit: size.height)
            resized.origin.y = y.origin
            resized.size.height = y.length
        }
        return resized
    }

    // MARK: Move and size change

    /// The box moved by `delta`. It stops at the edges of the screen, and its size stays.
    public func moved(by delta: CGPoint, in screenSize: CGSize) -> Selection {
        var moved = self
        moved.rect.origin.x = min(max((rect.minX + delta.x).rounded(), 0), max(screenSize.width - rect.width, 0))
        moved.rect.origin.y = min(max((rect.minY + delta.y).rounded(), 0), max(screenSize.height - rect.height, 0))
        return moved
    }

    /// The box after `handle` moved to `point`. The opposite edges stay in place.
    /// A handle that goes through the opposite edge turns the box over.
    public func resized(_ handle: Handle, to point: CGPoint, in screenSize: CGSize) -> Selection {
        var resized = self
        // The box stays on whole points. Its edges are whole already, so only the pointer is rounded.
        let whole = CGPoint(x: point.x.rounded(), y: point.y.rounded())
        resized.rect = Selection.resized(rect, by: handle, to: whole, in: screenSize)
        return resized
    }

    /// One axis of a rectangle, between an edge that stays and an edge that follows the pointer.
    /// The result is inside `0...limit`, and at least `minimumSide` long.
    private static func span(fixed: CGFloat, moving: CGFloat, limit: CGFloat) -> (origin: CGFloat, length: CGFloat) {
        let a = min(max(fixed, 0), limit)
        let b = min(max(moving, 0), limit)
        let length = max(abs(b - a), minimumSide)
        // A short rectangle grows from the fixed edge towards the pointer. At the edge of the
        // area it moves back in.
        let origin = b < a ? a - length : a
        return (min(max(origin, 0), max(limit - length, 0)), length)
    }

    // MARK: The label and the toolbar

    /// The text of the size label: the width and the height in points.
    public var sizeText: String {
        "\(Int(rect.width)) × \(Int(rect.height))"
    }

    /// The place of the size label: above the top-left corner of the box. With no room above,
    /// or with `obstacle` (the toolbar) in that place, it is inside the box at its top-left.
    /// It never leaves the screen at the right.
    public func labelFrame(labelSize: CGSize, in screenSize: CGSize, avoiding obstacle: CGRect = .null) -> CGRect {
        let gap = Selection.labelGap
        let lastX = max(screenSize.width - labelSize.width, 0)
        let above = CGRect(
            origin: CGPoint(x: min(rect.minX, lastX), y: rect.minY - gap - labelSize.height),
            size: labelSize
        )
        if above.minY >= 0, !above.intersects(obstacle) { return above }
        return CGRect(origin: CGPoint(x: min(rect.minX + gap, lastX), y: rect.minY + gap), size: labelSize)
    }

    /// The place of a toolbar of `size`: below the box, with its right edge on the right edge of
    /// the box. With no room below it is above the box. With no room above either, it is inside
    /// the box at the bottom-right. It never leaves the screen at the left or at the right.
    ///
    /// `tallestHeight` is the height of the toolbar with all its rows. The choice of the place
    /// uses it, so the toolbar does not jump when a row shows or hides.
    public func toolbarFrame(size: CGSize, tallestHeight: CGFloat, in screenSize: CGSize) -> CGRect {
        let gap = Selection.toolbarGap
        var origin = CGPoint(x: rect.maxX - size.width, y: rect.maxY + gap)
        if rect.maxY + gap + tallestHeight > screenSize.height {
            if rect.minY - gap - tallestHeight >= 0 {
                origin.y = rect.minY - gap - size.height
            } else {
                origin = CGPoint(x: rect.maxX - gap - size.width, y: rect.maxY - gap - size.height)
            }
        }
        origin.x = min(max(origin.x, 0), max(screenSize.width - size.width, 0))
        return CGRect(origin: origin, size: size)
    }
}
