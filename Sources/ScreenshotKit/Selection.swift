import CoreGraphics

/// The box of one capture: pure geometry.
///
/// The box is in the points of one screen. Its origin is the top-left of that screen.
/// It always uses whole points, so its edges are on whole pixels at scale 1 and at scale 2.
public struct Selection: Equatable {
    /// The smallest width and height of a box. A smaller box has no pixel to save.
    public static let minimumSide: CGFloat = 1

    public private(set) var rect: CGRect

    /// The box between the two ends of a drag, in any direction.
    /// The box stays inside a screen of `screenSize` points.
    public init(from start: CGPoint, to end: CGPoint, in screenSize: CGSize) {
        let a = Selection.wholePoint(start, in: screenSize)
        let b = Selection.wholePoint(end, in: screenSize)
        var rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
        // A drag in a straight line has no area. Give it the smallest side, still in the screen.
        if rect.width < Selection.minimumSide {
            rect.size.width = Selection.minimumSide
            rect.origin.x = min(rect.origin.x, screenSize.width - Selection.minimumSide)
        }
        if rect.height < Selection.minimumSide {
            rect.size.height = Selection.minimumSide
            rect.origin.y = min(rect.origin.y, screenSize.height - Selection.minimumSide)
        }
        self.rect = rect
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

    private static func wholePoint(_ point: CGPoint, in screenSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x.rounded(), 0), screenSize.width),
            y: min(max(point.y.rounded(), 0), screenSize.height)
        )
    }
}
