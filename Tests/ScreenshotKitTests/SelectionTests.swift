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

        // A drag in a straight line still has 1 point to save, also at the last edge of the screen.
        let line = Selection(from: CGPoint(x: 200, y: 100), to: CGPoint(x: 120, y: 100), in: screen)
        #expect(line.rect == CGRect(x: 120, y: 99, width: 80, height: 1))
        let dot = Selection(from: CGPoint(x: 200, y: 40), to: CGPoint(x: 200, y: 40), in: screen)
        #expect(dot.rect == CGRect(x: 199, y: 40, width: 1, height: 1))
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
}
