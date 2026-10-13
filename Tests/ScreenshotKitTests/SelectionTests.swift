import CoreGraphics
import ScreenshotKit
import Testing

@Suite struct SelectionTests {
    let screen = CGSize(width: 200, height: 100)

    @Test func aDragInEachOfTheFourDirectionsGivesTheSameBox() {
        let topLeft = CGPoint(x: 20, y: 10)
        let topRight = CGPoint(x: 150, y: 10)
        let bottomLeft = CGPoint(x: 20, y: 70)
        let bottomRight = CGPoint(x: 150, y: 70)
        let expected = CGRect(x: 20, y: 10, width: 130, height: 60)

        #expect(Selection(from: topLeft, to: bottomRight, in: screen).rect == expected)
        #expect(Selection(from: bottomRight, to: topLeft, in: screen).rect == expected)
        #expect(Selection(from: topRight, to: bottomLeft, in: screen).rect == expected)
        #expect(Selection(from: bottomLeft, to: topRight, in: screen).rect == expected)
    }

    @Test func theBoxStaysInTheScreenAndOnWholePoints() {
        // The pointer left the screen at the right and at the bottom.
        let pastTheEnd = Selection(from: CGPoint(x: 150, y: 60), to: CGPoint(x: 900, y: 400), in: screen)
        #expect(pastTheEnd.rect == CGRect(x: 150, y: 60, width: 50, height: 40))

        // The pointer left the screen at the left and at the top.
        let pastTheStart = Selection(from: CGPoint(x: 150, y: 60), to: CGPoint(x: -30, y: -5), in: screen)
        #expect(pastTheStart.rect == CGRect(x: 0, y: 0, width: 150, height: 60))

        // A pointer between two points gives whole points.
        let fractions = Selection(from: CGPoint(x: 10.4, y: 20.6), to: CGPoint(x: 50.5, y: 80.2), in: screen)
        #expect(fractions.rect == CGRect(x: 10, y: 21, width: 41, height: 59))

        // A drag in a straight line still gives the smallest box, also at the last edge of the screen.
        let line = Selection(from: CGPoint(x: 200, y: 100), to: CGPoint(x: 120, y: 100), in: screen)
        #expect(line.rect == CGRect(x: 120, y: 96, width: 80, height: 4))
        let dot = Selection(from: CGPoint(x: 200, y: 40), to: CGPoint(x: 200, y: 40), in: screen)
        #expect(dot.rect == CGRect(x: 196, y: 40, width: 4, height: 4))
    }

    @Test func thePixelRectangleForScale1AndScale2() {
        let selection = Selection(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70), in: screen)
        #expect(selection.pixelRect(scale: 1) == CGRect(x: 20, y: 10, width: 130, height: 60))
        #expect(selection.pixelRect(scale: 2) == CGRect(x: 40, y: 20, width: 260, height: 120))
    }

    @Test func containsUsesTheBoxWithoutItsFarEdges() {
        let selection = Selection(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70), in: screen)
        #expect(selection.contains(CGPoint(x: 20, y: 10)))
        #expect(selection.contains(CGPoint(x: 149, y: 69)))
        #expect(!selection.contains(CGPoint(x: 150, y: 70)))
        #expect(!selection.contains(CGPoint(x: 19, y: 30)))
    }

    // MARK: Move, size change, handles (YAZ-2766)

    /// A box of 60 by 40 points: x 50 to 110, y 30 to 70.
    var box: Selection { Selection(from: CGPoint(x: 50, y: 30), to: CGPoint(x: 110, y: 70), in: screen) }

    @Test func theHitTestFindsEachHandleAndTheInside() {
        let middles: [(Handle, CGPoint)] = [
            (.topLeft, CGPoint(x: 50, y: 30)), (.top, CGPoint(x: 80, y: 30)), (.topRight, CGPoint(x: 110, y: 30)),
            (.right, CGPoint(x: 110, y: 50)), (.bottomRight, CGPoint(x: 110, y: 70)),
            (.bottom, CGPoint(x: 80, y: 70)), (.bottomLeft, CGPoint(x: 50, y: 70)), (.left, CGPoint(x: 50, y: 50)),
        ]
        #expect(middles.count == Handle.allCases.count)
        for (handle, middle) in middles {
            #expect(box.handlePoint(handle) == middle)
            #expect(box.part(at: middle) == .handle(handle))
            // The hit area is 12 by 12 points: 6 points from the middle is in, 7 points is out.
            #expect(box.part(at: CGPoint(x: middle.x + 6, y: middle.y - 6)) == .handle(handle))
            #expect(box.part(at: CGPoint(x: middle.x - 6, y: middle.y + 6)) == .handle(handle))
            #expect(box.part(at: CGPoint(x: middle.x + 7, y: middle.y)) != .handle(handle))
            #expect(box.part(at: CGPoint(x: middle.x, y: middle.y - 7)) != .handle(handle))
        }
        #expect(box.part(at: CGPoint(x: 80, y: 50)) == .inside)
        #expect(box.part(at: CGPoint(x: 60, y: 38)) == .inside)
        #expect(box.part(at: CGPoint(x: 120, y: 50)) == nil)
        #expect(box.part(at: CGPoint(x: 10, y: 5)) == nil)

        // On the smallest box all hit areas overlap. The nearest handle wins, and a corner wins a tie.
        let small = Selection(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 104, y: 54), in: screen)
        #expect(small.part(at: CGPoint(x: 104, y: 54)) == .handle(.bottomRight))
        #expect(small.part(at: CGPoint(x: 102, y: 49)) == .handle(.top))
        #expect(small.part(at: CGPoint(x: 102, y: 52)) == .handle(.topLeft))
    }

    @Test func aMoveKeepsTheSizeAndStopsAtEachOfTheFourScreenEdges() {
        #expect(box.moved(by: CGPoint(x: 20, y: -10), in: screen).rect == CGRect(x: 70, y: 20, width: 60, height: 40))
        #expect(box.moved(by: CGPoint(x: -500, y: 0), in: screen).rect == CGRect(x: 0, y: 30, width: 60, height: 40))
        #expect(box.moved(by: CGPoint(x: 500, y: 0), in: screen).rect == CGRect(x: 140, y: 30, width: 60, height: 40))
        #expect(box.moved(by: CGPoint(x: 0, y: -500), in: screen).rect == CGRect(x: 50, y: 0, width: 60, height: 40))
        #expect(box.moved(by: CGPoint(x: 0, y: 500), in: screen).rect == CGRect(x: 50, y: 60, width: 60, height: 40))
        // A move between two points gives whole points.
        #expect(box.moved(by: CGPoint(x: 10.4, y: -2.6), in: screen).rect == CGRect(x: 60, y: 27, width: 60, height: 40))
    }

    @Test func aSizeChangeFromEachOfTheEightHandles() {
        // A corner changes two edges. An edge handle changes one edge, and ignores the other axis.
        let changes: [(Handle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: 40, y: 20), CGRect(x: 40, y: 20, width: 70, height: 50)),
            (.top, CGPoint(x: 199, y: 20), CGRect(x: 50, y: 20, width: 60, height: 50)),
            (.topRight, CGPoint(x: 130, y: 20), CGRect(x: 50, y: 20, width: 80, height: 50)),
            (.right, CGPoint(x: 130, y: 5), CGRect(x: 50, y: 30, width: 80, height: 40)),
            (.bottomRight, CGPoint(x: 130, y: 90), CGRect(x: 50, y: 30, width: 80, height: 60)),
            (.bottom, CGPoint(x: 0, y: 90), CGRect(x: 50, y: 30, width: 60, height: 60)),
            (.bottomLeft, CGPoint(x: 40, y: 90), CGRect(x: 40, y: 30, width: 70, height: 60)),
            (.left, CGPoint(x: 40, y: 0), CGRect(x: 40, y: 30, width: 70, height: 40)),
        ]
        #expect(changes.count == Handle.allCases.count)
        for (handle, point, expected) in changes {
            #expect(box.resized(handle, to: point, in: screen).rect == expected, "handle \(handle)")
        }
        // A size change stops at the edges of the screen.
        #expect(box.resized(.bottomRight, to: CGPoint(x: 900, y: 900), in: screen).rect
            == CGRect(x: 50, y: 30, width: 150, height: 70))
        #expect(box.resized(.topLeft, to: CGPoint(x: -50, y: -50), in: screen).rect
            == CGRect(x: 0, y: 0, width: 110, height: 70))
    }

    @Test func aSizeChangeThroughTheOppositeEdgeTurnsTheBoxOverAndTheSmallestBoxIs4By4() {
        // Through the opposite edge: that edge stays, and the box is on its other side.
        #expect(box.resized(.left, to: CGPoint(x: 150, y: 0), in: screen).rect == CGRect(x: 110, y: 30, width: 40, height: 40))
        #expect(box.resized(.bottom, to: CGPoint(x: 0, y: 10), in: screen).rect == CGRect(x: 50, y: 10, width: 60, height: 20))
        #expect(box.resized(.topLeft, to: CGPoint(x: 150, y: 90), in: screen).rect == CGRect(x: 110, y: 70, width: 40, height: 20))

        // The box never gets smaller than 4 points, on each side of the edge that stays.
        #expect(box.resized(.right, to: CGPoint(x: 51, y: 0), in: screen).rect == CGRect(x: 50, y: 30, width: 4, height: 40))
        #expect(box.resized(.right, to: CGPoint(x: 49, y: 0), in: screen).rect == CGRect(x: 46, y: 30, width: 4, height: 40))
        #expect(box.resized(.bottomRight, to: CGPoint(x: 50, y: 30), in: screen).rect == CGRect(x: 50, y: 30, width: 4, height: 4))

        // The first drag has the same rule. A short box grows towards the pointer, and stays in the screen.
        #expect(Selection(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 12), in: screen).rect
            == CGRect(x: 10, y: 10, width: 4, height: 4))
        #expect(Selection(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 9, y: 9), in: screen).rect
            == CGRect(x: 6, y: 6, width: 4, height: 4))
        #expect(Selection(from: CGPoint(x: 1, y: 1), to: CGPoint(x: -5, y: -5), in: screen).rect
            == CGRect(x: 0, y: 0, width: 4, height: 4))
        #expect(Selection(from: CGPoint(x: 200, y: 100), to: CGPoint(x: 200, y: 100), in: screen).rect
            == CGRect(x: 196, y: 96, width: 4, height: 4))
    }

    @Test func aBoxFromAWindowFrameIsCutToTheScreen() {
        #expect(Selection(rect: CGRect(x: 150.4, y: -20, width: 100, height: 60.3), in: screen)?.rect
            == CGRect(x: 150, y: 0, width: 50, height: 40))
        // Less than the smallest box on the screen: no box.
        #expect(Selection(rect: CGRect(x: 198, y: 10, width: 100, height: 60), in: screen) == nil)
        #expect(Selection(rect: CGRect(x: 300, y: 10, width: 100, height: 60), in: screen) == nil)
    }

    @Test func thePlaceOfTheSizeLabel() {
        let label = CGSize(width: 60, height: 18)
        #expect(box.sizeText == "60 × 40")

        // 1. Above the top-left corner of the box.
        #expect(box.labelFrame(labelSize: label, in: screen) == CGRect(x: 50, y: 8, width: 60, height: 18))

        // 2. No room above: inside the box, at its top-left.
        let atTheTop = Selection(from: CGPoint(x: 50, y: 10), to: CGPoint(x: 110, y: 70), in: screen)
        #expect(atTheTop.labelFrame(labelSize: label, in: screen) == CGRect(x: 54, y: 14, width: 60, height: 18))

        // 3. At the right edge of the screen the label moves left, so it stays on the screen.
        let atTheRight = Selection(from: CGPoint(x: 170, y: 40), to: CGPoint(x: 200, y: 80), in: screen)
        #expect(atTheRight.labelFrame(labelSize: label, in: screen) == CGRect(x: 140, y: 18, width: 60, height: 18))

        // The toolbar is above the box and covers the place: the label goes inside.
        let toolbar = CGRect(x: 40, y: 0, width: 100, height: 26)
        #expect(box.labelFrame(labelSize: label, in: screen, avoiding: toolbar) == CGRect(x: 54, y: 34, width: 60, height: 18))
        let toolbarBelow = CGRect(x: 40, y: 78, width: 100, height: 20)
        #expect(box.labelFrame(labelSize: label, in: screen, avoiding: toolbarBelow) == CGRect(x: 50, y: 8, width: 60, height: 18))
    }

    /// Rows 2 to 5 of YAZ-2767, on a screen of 400 by 300 points.
    @Test func thePlaceOfTheToolbar() {
        let large = CGSize(width: 400, height: 300)
        let oneRow = CGSize(width: 120, height: 36)
        let twoRows = CGSize(width: 120, height: 72)
        func place(_ rect: CGRect, _ size: CGSize) -> CGRect? {
            Selection(rect: rect, in: large)?.toolbarFrame(size: size, tallestHeight: 72, in: large)
        }

        // Below the box, with its right edge on the right edge of the box.
        #expect(place(CGRect(x: 100, y: 50, width: 200, height: 100), oneRow) == CGRect(x: 180, y: 158, width: 120, height: 36))
        #expect(place(CGRect(x: 100, y: 50, width: 200, height: 100), twoRows) == CGRect(x: 180, y: 158, width: 120, height: 72))

        // No room below: above the box.
        #expect(place(CGRect(x: 100, y: 150, width: 200, height: 100), oneRow) == CGRect(x: 180, y: 106, width: 120, height: 36))
        #expect(place(CGRect(x: 100, y: 150, width: 200, height: 100), twoRows) == CGRect(x: 180, y: 70, width: 120, height: 72))
        // One row has room below here, but two rows do not. The toolbar is above for the two sizes,
        // so it does not jump when the second row shows.
        #expect(place(CGRect(x: 100, y: 90, width: 200, height: 160), oneRow) == CGRect(x: 180, y: 46, width: 120, height: 36))

        // No room below and no room above: inside the box, at the bottom-right.
        #expect(place(CGRect(x: 100, y: 0, width: 200, height: 300), oneRow) == CGRect(x: 172, y: 256, width: 120, height: 36))
        #expect(place(CGRect(x: 100, y: 40, width: 200, height: 250), twoRows) == CGRect(x: 172, y: 210, width: 120, height: 72))

        // The toolbar never leaves the screen at the left, also when it is wider than the screen.
        #expect(place(CGRect(x: 10, y: 50, width: 60, height: 100), oneRow) == CGRect(x: 0, y: 158, width: 120, height: 36))
        #expect(place(CGRect(x: 10, y: 50, width: 60, height: 100), CGSize(width: 500, height: 36))?.minX == 0)
        // At the right, the box itself stops at the screen, and the toolbar ends with the box.
        #expect(place(CGRect(x: 300, y: 50, width: 100, height: 100), oneRow)?.maxX == 400)
    }
}
