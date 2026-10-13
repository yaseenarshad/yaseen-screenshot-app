import CoreGraphics
import ScreenshotKit
import Testing

/// The rules of one capture, with no window: the box (YAZ-2765 rows 17 to 27 and YAZ-2766),
/// the marks (YAZ-2767) and the click on a window (YAZ-2769).
@Suite struct CaptureInteractionTests {
    let retina = FakeScreenCapture.retinaID // 200 x 100 points
    let plain = FakeScreenCapture.plainID // 300 x 150 points

    /// An interaction on the two fake screens, with a record of what it reported.
    final class Harness {
        let interaction: CaptureInteraction
        var changes = 0
        var outcomes: [CaptureOutcome] = []

        /// Each harness has its own style memory, so one test does not change the styles of the next.
        init(windows: [CGDirectDisplayID: [CGRect]] = [:], styles: ToolStyleMemory = ToolStyleMemory()) async throws {
            interaction = CaptureInteraction(
                displays: try await FakeScreenCapture().freezeAllDisplays(), windows: windows, styles: styles
            )
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

        var doneResult: CaptureResult? {
            if case .done(let result)? = outcomes.first, outcomes.count == 1 { return result }
            return nil
        }

        var doneSelection: Selection? { doneResult?.selection }

        func click(at point: CGPoint, on displayID: CGDirectDisplayID) {
            drag(from: point, to: point, on: displayID)
        }

        func rect(on displayID: CGDirectDisplayID) -> CGRect? {
            interaction.selection(on: displayID)?.rect
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
        // The smallest box is 4 by 4 points (YAZ-2766 row 6).
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 50, y: 50, width: 4, height: 4))
        #expect(!interaction.showsHint)
        #expect(harness.changes == 1)

        // After the box started, it follows the pointer back to below 3 points.
        interaction.pointerDragged(to: CGPoint(x: 51, y: 52))
        interaction.pointerDragged(to: CGPoint(x: 51, y: 58))
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 50, y: 50, width: 4, height: 8))
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

        // A drag that starts in the box does not make a new box. It moves the box (YAZ-2766 row 2).
        harness.drag(from: CGPoint(x: 30, y: 20), to: CGPoint(x: 70, y: 45), on: retina)
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 60, y: 35, width: 60, height: 40))

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

    // MARK: Move and size change (YAZ-2766)

    @Test func aDragInTheBoxMovesItAndADragOfAHandleChangesItsSize() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction

        // During the first drag the box has no handles and no toolbar. They show at the release.
        interaction.pointerDown(at: CGPoint(x: 40, y: 20), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 120, y: 70))
        #expect(!interaction.showsHandles && !interaction.showsToolbar(on: retina))
        interaction.pointerUp(at: CGPoint(x: 120, y: 70))
        #expect(interaction.showsHandles && interaction.showsToolbar(on: retina))
        #expect(!interaction.showsToolbar(on: plain))
        #expect(harness.rect(on: retina) == CGRect(x: 40, y: 20, width: 80, height: 50))

        // The pointer shape tells what a drag does.
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .crosshair)
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: plain) == .crosshair)
        #expect(interaction.pointerShape(at: CGPoint(x: 80, y: 45), on: retina) == .openHand)
        #expect(interaction.pointerShape(at: CGPoint(x: 122, y: 45), on: retina) == .resize(.right))
        #expect(interaction.pointerShape(at: CGPoint(x: 38, y: 21), on: retina) == .resize(.topLeft))

        // A move of less than 3 points is a click: the box stays.
        harness.drag(from: CGPoint(x: 60, y: 40), to: CGPoint(x: 62, y: 41), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 40, y: 20, width: 80, height: 50))

        // A drag inside moves the box, and the toolbar and the handles stay during the move.
        interaction.pointerDown(at: CGPoint(x: 60, y: 40), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 90, y: 50))
        #expect(harness.rect(on: retina) == CGRect(x: 70, y: 30, width: 80, height: 50))
        #expect(interaction.showsHandles && interaction.showsToolbar(on: retina))
        #expect(interaction.pointerShape(at: CGPoint(x: 90, y: 50), on: retina) == .closedHand)
        // The box stops at the edges of its screen, and its size does not change.
        interaction.pointerDragged(to: CGPoint(x: 900, y: 900))
        #expect(harness.rect(on: retina) == CGRect(x: 120, y: 50, width: 80, height: 50))
        interaction.pointerUp(at: CGPoint(x: -900, y: -900))
        #expect(harness.rect(on: retina) == CGRect(x: 0, y: 0, width: 80, height: 50))

        // An edge handle changes one edge. The pointer took the handle 2 points from its middle,
        // and the edge keeps that distance.
        harness.drag(from: CGPoint(x: 82, y: 27), to: CGPoint(x: 112, y: 90), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 0, y: 0, width: 110, height: 50))
        // A corner handle changes two edges.
        harness.drag(from: CGPoint(x: 111, y: 49), to: CGPoint(x: 151, y: 79), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 0, y: 0, width: 150, height: 80))
        // Through the opposite edge the box turns over, and it stays correct.
        interaction.pointerDown(at: CGPoint(x: 0, y: 40), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 190, y: 40))
        #expect(interaction.pointerShape(at: CGPoint(x: 190, y: 40), on: retina) == .resize(.left))
        interaction.pointerUp(at: CGPoint(x: 190, y: 40))
        #expect(harness.rect(on: retina) == CGRect(x: 150, y: 0, width: 40, height: 80))
        #expect(harness.outcomes.isEmpty)
    }

    // MARK: Tools and marks (YAZ-2767)

    /// A harness with a box of 100 by 60 points on the retina screen: x 40 to 140, y 20 to 80.
    private func harnessWithBox(styles: ToolStyleMemory = ToolStyleMemory()) async throws -> Harness {
        let harness = try await Harness(styles: styles)
        harness.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        return harness
    }

    private let boxRect = CGRect(x: 40, y: 20, width: 100, height: 60)

    @Test func withAToolADragInTheBoxAddsAMarkAndWithAMarkTheBoxIsFixed() async throws {
        let harness = try await harnessWithBox()
        let interaction = harness.interaction

        // No tool can be selected with no box, and a click on the selected tool clears it.
        interaction.selectTool(.rectangle)
        #expect(interaction.tool == .rectangle)
        #expect(interaction.style == MarkStyle(color: .red, size: .medium))
        interaction.selectTool(.rectangle)
        #expect(interaction.tool == nil && interaction.style == nil)
        interaction.selectTool(.rectangle)

        // With a tool and no mark, the handles still show, and a drag in the box draws.
        #expect(interaction.showsHandles)
        #expect(interaction.pointerShape(at: CGPoint(x: 80, y: 50), on: retina) == .crosshair)
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .arrow)
        interaction.pointerDown(at: CGPoint(x: 60, y: 30), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 90, y: 50))
        // The mark shows during the drag, but it is in the list only after the release.
        #expect(interaction.visibleMarks.count == 1 && interaction.marks.isEmpty)
        interaction.pointerUp(at: CGPoint(x: 100, y: 60))
        // The points are in the points of the box. The box did not move.
        #expect(interaction.marks.marks == [
            Mark(tool: .rectangle, style: MarkStyle(color: .red, size: .medium), points: [CGPoint(x: 20, y: 10), CGPoint(x: 60, y: 40)]),
        ])
        #expect(harness.rect(on: retina) == boxRect)

        // A drag of less than 3 points draws no mark.
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 61, y: 32), on: retina)
        #expect(interaction.marks.marks.count == 1)
        // A drag that starts outside the box does nothing.
        harness.drag(from: CGPoint(x: 10, y: 5), to: CGPoint(x: 100, y: 60), on: retina)
        harness.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 60), on: plain)
        #expect(interaction.marks.marks.count == 1)
        #expect(harness.rect(on: retina) == boxRect && harness.rect(on: plain) == nil)

        // A mark cannot leave the box: its points stop at the edges, half a line width inside.
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 900, y: 900), on: retina)
        #expect(interaction.marks.marks.last?.points == [CGPoint(x: 20, y: 10), CGPoint(x: 98, y: 58)])
        interaction.selectTool(.pen)
        interaction.pointerDown(at: CGPoint(x: 60, y: 30), on: retina)
        for point in [CGPoint(x: 70, y: 40), CGPoint(x: -50, y: 40), CGPoint(x: 90, y: -50), CGPoint(x: 90, y: 500)] {
            interaction.pointerDragged(to: point)
        }
        interaction.pointerUp(at: CGPoint(x: 90, y: 500))
        let pen = try #require(interaction.marks.marks.last)
        #expect(pen.points == [
            CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 20), CGPoint(x: 2, y: 20), CGPoint(x: 50, y: 2), CGPoint(x: 50, y: 58),
        ])
        #expect(interaction.marks.marks.count == 3)

        // With a tool selected, a double-click does not mean Done.
        interaction.doubleClick(at: CGPoint(x: 80, y: 50), on: retina)
        #expect(harness.outcomes.isEmpty)

        // With marks and no tool the box is fixed: no handles, no move, no size change, no new box.
        interaction.selectTool(.pen)
        #expect(interaction.tool == nil)
        #expect(!interaction.showsHandles && interaction.showsToolbar(on: retina))
        #expect(interaction.pointerShape(at: CGPoint(x: 80, y: 50), on: retina) == .arrow)
        #expect(interaction.pointerShape(at: CGPoint(x: 140, y: 80), on: retina) == .arrow)
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: plain) == .arrow)
        harness.drag(from: CGPoint(x: 80, y: 50), to: CGPoint(x: 120, y: 70), on: retina) // inside
        harness.drag(from: CGPoint(x: 140, y: 80), to: CGPoint(x: 180, y: 95), on: retina) // a handle
        harness.drag(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 30, y: 15), on: retina) // outside
        harness.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 60), on: plain) // a different screen
        #expect(harness.rect(on: retina) == boxRect && harness.rect(on: plain) == nil)
        // A right-click does nothing while marks exist.
        interaction.secondaryClick()
        #expect(harness.rect(on: retina) == boxRect && harness.outcomes.isEmpty)

        // With no tool, a double-click in the box means Done, and the result has the marks.
        interaction.doubleClick(at: CGPoint(x: 80, y: 50), on: retina)
        #expect(harness.doneResult?.marks.marks.count == 3)
        #expect(harness.doneSelection?.rect == boxRect)
    }

    @Test func undoAndRedoAndTheHandlesComeBackAfterTheLastMark() async throws {
        let harness = try await harnessWithBox()
        let interaction = harness.interaction
        #expect(!interaction.canUndo)
        interaction.key(.undo) // no mark: nothing
        interaction.selectTool(.arrow)
        harness.drag(from: CGPoint(x: 50, y: 30), to: CGPoint(x: 90, y: 60), on: retina)
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 100, y: 60), on: retina)
        interaction.selectTool(.arrow)
        let two = interaction.marks.marks
        #expect(two.count == 2 && interaction.canUndo && !interaction.showsHandles)

        let revision = interaction.marksRevision
        interaction.key(.undo)
        #expect(interaction.marks.marks == [two[0]])
        #expect(interaction.marksRevision > revision)
        interaction.key(.redo)
        #expect(interaction.marks.marks == two)
        interaction.key(.redo)
        #expect(interaction.marks.marks == two)

        // The last mark is removed with Undo: the box is free again and has its handles.
        interaction.undo()
        interaction.undo()
        interaction.undo()
        #expect(interaction.marks.isEmpty && interaction.showsHandles && !interaction.canUndo)
        interaction.redo()
        #expect(interaction.marks.marks == [two[0]] && !interaction.showsHandles)

        // A change of the box clears the Redo list: those marks belong to the old box.
        interaction.undo()
        harness.drag(from: CGPoint(x: 80, y: 50), to: CGPoint(x: 90, y: 50), on: retina)
        #expect(harness.rect(on: retina) == boxRect.offsetBy(dx: 10, dy: 0))
        interaction.redo()
        #expect(interaction.marks.isEmpty)

        // A right-click now removes the box, and with it the selected tool.
        interaction.selectTool(.pen)
        interaction.secondaryClick()
        #expect(harness.rect(on: retina) == nil && interaction.tool == nil && harness.outcomes.isEmpty)
        interaction.selectTool(.pen)
        #expect(interaction.tool == nil)
    }

    @Test func eachToolRemembersItsOwnColourAndSize() async throws {
        let styles = ToolStyleMemory()
        let harness = try await harnessWithBox(styles: styles)
        let interaction = harness.interaction

        // Without a selected tool, a colour has no target.
        interaction.setColor(.white)
        interaction.selectTool(.highlight)
        #expect(interaction.style == MarkStyle(color: .amber, size: .medium))
        interaction.setColor(.green)
        interaction.setSize(.thick)
        interaction.selectTool(.pen)
        #expect(interaction.style == MarkStyle(color: .red, size: .medium))
        interaction.setColor(.blue)
        interaction.selectTool(.highlight)
        #expect(interaction.style == MarkStyle(color: .green, size: .thick))

        // A change of the colour applies to the next mark. It does not change a mark that exists.
        interaction.selectTool(.pen)
        harness.drag(from: CGPoint(x: 50, y: 30), to: CGPoint(x: 90, y: 60), on: retina)
        interaction.setColor(.black)
        interaction.setSize(.thin)
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 100, y: 60), on: retina)
        #expect(interaction.marks.marks.map(\.style) == [
            MarkStyle(color: .blue, size: .medium), MarkStyle(color: .black, size: .thin),
        ])

        // The next capture of the app starts with the same styles.
        let next = try await harnessWithBox(styles: styles)
        next.interaction.selectTool(.pen)
        #expect(next.interaction.style == MarkStyle(color: .black, size: .thin))
        next.interaction.selectTool(.highlight)
        #expect(next.interaction.style == MarkStyle(color: .green, size: .thick))
        next.interaction.selectTool(.ellipse)
        #expect(next.interaction.style == MarkStyle(color: .red, size: .medium))
    }

    @Test func theRulesOfTheTextTool() async throws {
        let harness = try await harnessWithBox()
        let interaction = harness.interaction
        interaction.selectTool(.text)
        #expect(interaction.pointerShape(at: CGPoint(x: 80, y: 50), on: retina) == .iBeam)

        // A click outside the box puts no text.
        harness.click(at: CGPoint(x: 10, y: 5), on: retina)
        #expect(interaction.textEdit == nil)

        // A click in the box puts a text there. The click is the middle of the first line
        // (Medium is 18 points, and its line is 23 points). The line breaks at the right edge of the box.
        harness.click(at: CGPoint(x: 60, y: 50), on: retina)
        let edit = try #require(interaction.textEdit)
        #expect(edit.origin == CGPoint(x: 20, y: 19) && edit.wrapWidth == 80 && edit.text.isEmpty)
        #expect(edit.style == MarkStyle(color: .red, size: .medium))
        #expect(!interaction.showsHandles)
        // A right-click does nothing while a text is open.
        interaction.secondaryClick()
        #expect(interaction.textEdit != nil && harness.rect(on: retina) == boxRect)

        // An empty text adds no mark, and a text of only spaces adds no mark.
        interaction.completeText()
        #expect(interaction.textEdit == nil && interaction.marks.isEmpty)
        harness.click(at: CGPoint(x: 60, y: 50), on: retina)
        interaction.textChanged("  \n ")
        interaction.completeText()
        #expect(interaction.marks.isEmpty && interaction.showsHandles)

        // Return completes the text (the view calls `completeText`).
        harness.click(at: CGPoint(x: 60, y: 50), on: retina)
        interaction.textChanged("One")
        // A change of the colour while the text is open applies to that text.
        interaction.setColor(.blue)
        interaction.completeText()
        let one = Mark(
            tool: .text, style: MarkStyle(color: .blue, size: .medium), points: [CGPoint(x: 20, y: 19)], text: "One", wrapWidth: 80
        )
        #expect(interaction.marks.marks == [one])

        // A click in a different place also completes the text, and puts a new text there.
        // Near the right and the bottom edge, the text moves into the box.
        harness.click(at: CGPoint(x: 50, y: 40), on: retina)
        interaction.textChanged("Two")
        harness.click(at: CGPoint(x: 139, y: 79), on: retina)
        #expect(interaction.marks.marks.count == 2 && interaction.marks.marks.last?.text == "Two")
        #expect(interaction.textEdit?.origin == CGPoint(x: 64, y: 37))
        #expect(interaction.textEdit?.wrapWidth == 36)

        // Esc removes the text that is not complete, and the capture stays open.
        interaction.textChanged("Three")
        interaction.key(.escape)
        #expect(interaction.textEdit == nil && interaction.marks.marks.count == 2 && harness.outcomes.isEmpty)

        // Undo with an open text: the text is completed, and then it is the mark that Undo removes.
        harness.click(at: CGPoint(x: 50, y: 40), on: retina)
        interaction.textChanged("Four")
        #expect(interaction.canUndo)
        interaction.undo()
        #expect(interaction.textEdit == nil && interaction.marks.marks.map(\.text) == ["One", "Two"])
        interaction.redo()
        #expect(interaction.marks.marks.map(\.text) == ["One", "Two", "Four"])

        // A click on a different tool completes the open text.
        harness.click(at: CGPoint(x: 50, y: 60), on: retina)
        interaction.textChanged("Five")
        interaction.selectTool(.pen)
        #expect(interaction.textEdit == nil && interaction.marks.marks.last?.text == "Five")

        // Done while a text is not complete: the text is completed first, and then the capture ends.
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 100, y: 60), on: retina)
        interaction.textChanged("Last")
        interaction.key(.enter)
        #expect(harness.doneResult?.marks.marks.map(\.text) == ["One", "Two", "Four", "Five", "Last"])
    }

    @Test func escWithAnOpenTextAndThenEscAgainCancels() async throws {
        let harness = try await harnessWithBox()
        harness.interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 60, y: 50), on: retina)
        harness.interaction.key(.escape)
        #expect(harness.outcomes.isEmpty)
        harness.interaction.key(.escape)
        #expect(harness.isCancelled)
    }

    // MARK: The click on a window (YAZ-2769)

    /// Two windows on the retina screen. The first is in front. They overlap from x 60 to 120, y 30 to 70.
    private let front = CGRect(x: 20, y: 10, width: 100, height: 60)
    private let back = CGRect(x: 60, y: 30, width: 120, height: 60)

    @Test func theWindowBelowThePointerIsBrightUntilABoxExists() async throws {
        let harness = try await Harness(windows: [retina: [front, back], plain: [CGRect(x: 0, y: 0, width: 300, height: 150)]])
        let interaction = harness.interaction
        #expect(interaction.highlight(on: retina) == nil && interaction.highlight(on: plain) == nil)

        interaction.pointerMoved(to: CGPoint(x: 30, y: 20), on: retina)
        #expect(interaction.highlight(on: retina) == front)
        // The highlight shows only on the screen that has the pointer.
        #expect(interaction.highlight(on: plain) == nil)
        #expect(harness.changes == 1)

        // A move on the same window changes nothing, so the views do not draw again.
        interaction.pointerMoved(to: CGPoint(x: 35, y: 25), on: retina)
        // Two windows overlap: the window in front at the pointer is the one.
        interaction.pointerMoved(to: CGPoint(x: 80, y: 40), on: retina)
        #expect(interaction.highlight(on: retina) == front)
        #expect(harness.changes == 1)

        // The pointer moves to a different window: the highlight moves to that window.
        interaction.pointerMoved(to: CGPoint(x: 150, y: 80), on: retina)
        #expect(interaction.highlight(on: retina) == back)
        #expect(harness.changes == 2)
        // No window below the pointer: nothing is bright.
        interaction.pointerMoved(to: CGPoint(x: 190, y: 5), on: retina)
        #expect(interaction.highlight(on: retina) == nil)
        #expect(harness.changes == 3)
        // The pointer goes to the other screen.
        interaction.pointerMoved(to: CGPoint(x: 30, y: 20), on: plain)
        #expect(interaction.highlight(on: retina) == nil)
        #expect(interaction.highlight(on: plain) == CGRect(x: 0, y: 0, width: 300, height: 150))
        #expect(interaction.showsHint)
    }

    @Test func theWindowListCanArriveAfterTheCaptureStarted() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction
        interaction.pointerMoved(to: CGPoint(x: 30, y: 20), on: retina)
        #expect(interaction.highlight(on: retina) == nil && harness.changes == 0)

        // The list arrives: the window below the pointer is bright at once.
        interaction.setWindows([retina: [front, back]])
        #expect(interaction.highlight(on: retina) == front && harness.changes == 1)
        harness.click(at: CGPoint(x: 30, y: 20), on: retina)
        #expect(harness.rect(on: retina) == front)
    }

    @Test func aClickOnAWindowGivesItsBoxAndADragGivesAFreeBox() async throws {
        let harness = try await Harness(windows: [retina: [front, back]])
        let interaction = harness.interaction

        // A click with no drag where no window is: nothing happens.
        harness.click(at: CGPoint(x: 190, y: 5), on: retina)
        harness.click(at: CGPoint(x: 30, y: 20), on: plain)
        #expect(interaction.showsHint && harness.outcomes.isEmpty)

        // A click on a window (a move of less than 3 points is still a click): the box is that window,
        // with the handles and the toolbar, as after a drag.
        harness.drag(from: CGPoint(x: 150, y: 80), to: CGPoint(x: 151, y: 81), on: retina)
        #expect(harness.rect(on: retina) == back)
        #expect(interaction.showsHandles && interaction.showsToolbar(on: retina))
        // After a box exists, the highlight does not show, and a click on a window changes nothing.
        interaction.pointerMoved(to: CGPoint(x: 30, y: 20), on: retina)
        #expect(interaction.highlight(on: retina) == nil)
        harness.click(at: CGPoint(x: 30, y: 20), on: retina)
        #expect(harness.rect(on: retina) == back)

        // After a right-click removes the box, the highlight shows again.
        interaction.secondaryClick()
        #expect(harness.rect(on: retina) == nil)
        #expect(interaction.highlight(on: retina) == front)

        // A drag of 3 points or more makes a free box. It does not use the window.
        harness.drag(from: CGPoint(x: 30, y: 20), to: CGPoint(x: 70, y: 50), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 30, y: 20, width: 40, height: 30))
        interaction.secondaryClick()

        // A double-click on a window: the first click selects it, and the second means Done.
        harness.click(at: CGPoint(x: 30, y: 20), on: retina)
        interaction.pointerDown(at: CGPoint(x: 30, y: 20), on: retina)
        interaction.doubleClick(at: CGPoint(x: 30, y: 20), on: retina)
        #expect(harness.doneSelection?.rect == front)
    }
}
