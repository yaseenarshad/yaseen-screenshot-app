import CoreGraphics
import ScreenshotKit
import Testing

/// The rules of the box (scenario rows 17 to 27 of YAZ-2765), with no window.
@Suite struct CaptureInteractionTests {
    let retina = FakeScreenCapture.retinaID // 200 x 100 points
    let plain = FakeScreenCapture.plainID // 300 x 150 points

    /// An interaction on the two fake screens, with a record of what it reported.
    final class Harness {
        let interaction: CaptureInteraction
        var changes = 0
        var outcomes: [CaptureOutcome] = []

        init() async throws {
            interaction = CaptureInteraction(displays: try await FakeScreenCapture().freezeAllDisplays())
            interaction.onChange = { [unowned self] in self.changes += 1 }
            interaction.onFinish = { [unowned self] in self.outcomes.append($0) }
        }

        func drag(from start: CGPoint, to end: CGPoint, on displayID: CGDirectDisplayID) {
            interaction.pointerDown(at: start, on: displayID)
            interaction.pointerDragged(to: end)
            interaction.pointerUp(at: end)
        }

        var isCancelled: Bool {
            if case .cancel? = outcomes.first, outcomes.count == 1 { return true }
            return false
        }

        var doneSelection: Selection? {
            if case .done(let result)? = outcomes.first, outcomes.count == 1 { return result.selection }
            return nil
        }
    }

    @Test func aDragOfLessThan3PointsMakesNoBox() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction
        #expect(interaction.showsHint)

        interaction.pointerDown(at: CGPoint(x: 50, y: 50), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 52, y: 51))
        interaction.pointerUp(at: CGPoint(x: 52, y: 51))
        #expect(interaction.selection(on: retina) == nil)
        #expect(interaction.showsHint)
        #expect(harness.changes == 0)

        // At 3 points the box starts, and the hint goes away.
        interaction.pointerDown(at: CGPoint(x: 50, y: 50), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 53, y: 50))
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 50, y: 50, width: 3, height: 1))
        #expect(!interaction.showsHint)
        #expect(harness.changes == 1)

        // After the box started, it follows the pointer back to below 3 points.
        interaction.pointerDragged(to: CGPoint(x: 51, y: 52))
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 50, y: 50, width: 1, height: 2))
    }

    @Test func theBoxStaysOnTheScreenWhereTheDragStarted() async throws {
        let harness = try await Harness()
        // The pointer goes far to the right, onto the other screen. The box stops at the edge.
        harness.drag(from: CGPoint(x: 150, y: 20), to: CGPoint(x: 420, y: 60), on: retina)
        #expect(harness.interaction.selection(on: retina)?.rect == CGRect(x: 150, y: 20, width: 50, height: 40))
        #expect(harness.interaction.selection(on: plain) == nil)
        #expect(harness.interaction.selectionDisplayID == retina)
    }

    @Test func aNewDragReplacesTheBoxAndOnlyOneBoxExists() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction
        let first = CGRect(x: 20, y: 10, width: 60, height: 40)
        harness.drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 80, y: 50), on: retina)
        #expect(interaction.selection(on: retina)?.rect == first)

        // A click outside the box with no drag keeps the box.
        harness.drag(from: CGPoint(x: 150, y: 80), to: CGPoint(x: 150, y: 80), on: retina)
        #expect(interaction.selection(on: retina)?.rect == first)

        // A drag that starts in the box does not make a new box.
        harness.drag(from: CGPoint(x: 30, y: 20), to: CGPoint(x: 70, y: 45), on: retina)
        #expect(interaction.selection(on: retina)?.rect == first)

        // A drag outside the box makes a new box.
        harness.drag(from: CGPoint(x: 190, y: 90), to: CGPoint(x: 120, y: 60), on: retina)
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 120, y: 60, width: 70, height: 30))

        // A drag on a different screen moves the box to that screen.
        harness.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 250, y: 140), on: plain)
        #expect(interaction.selection(on: retina) == nil)
        #expect(interaction.selection(on: plain)?.rect == CGRect(x: 10, y: 10, width: 240, height: 130))
        #expect(harness.outcomes.isEmpty)
    }

    @Test func enterNeedsABoxAndADoubleClickMustBeInTheBox() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction

        interaction.key(.enter)
        #expect(harness.outcomes.isEmpty)

        harness.drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 80, y: 50), on: retina)
        interaction.doubleClick(at: CGPoint(x: 150, y: 80), on: retina) // outside the box
        interaction.doubleClick(at: CGPoint(x: 30, y: 20), on: plain) // the same point on the other screen
        #expect(harness.outcomes.isEmpty)

        interaction.doubleClick(at: CGPoint(x: 30, y: 20), on: retina)
        #expect(harness.doneSelection?.rect == CGRect(x: 20, y: 10, width: 60, height: 40))

        // A finished capture ignores each later call. It reports one time only.
        interaction.key(.enter)
        interaction.key(.escape)
        interaction.secondaryClick()
        harness.drag(from: CGPoint(x: 100, y: 60), to: CGPoint(x: 180, y: 90), on: retina)
        #expect(harness.outcomes.count == 1)
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 20, y: 10, width: 60, height: 40))
    }

    @Test func aRightClickRemovesTheBoxAndThenCancels() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction
        harness.drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 80, y: 50), on: retina)

        interaction.secondaryClick()
        #expect(interaction.selection(on: retina) == nil)
        #expect(interaction.showsHint)
        #expect(harness.outcomes.isEmpty)

        interaction.secondaryClick()
        #expect(harness.isCancelled)
    }
}
