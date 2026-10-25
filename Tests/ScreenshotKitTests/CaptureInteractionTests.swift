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
        /// The toolbar keys are in memory, so a test never reads the keys of the user.
        init(
            windows: [CGDirectDisplayID: [CGRect]] = [:],
            styles: ToolStyleMemory = ToolStyleMemory(),
            toolbarKeys: ToolbarKeys = ToolbarKeys(defaults: MemoryDefaults()),
            startTool: Tool? = nil,
            clipboard: MarkClipboard = MarkClipboard()
        ) async throws {
            interaction = CaptureInteraction(
                displays: try await FakeScreenCapture().freezeAllDisplays(),
                windows: windows,
                toolbarKeys: toolbarKeys,
                startTool: startTool,
                styles: styles,
                clipboard: clipboard
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

        interaction.pointerDown(at: CGPoint(x: 50, y: 50), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 52, y: 51))
        interaction.pointerUp(at: CGPoint(x: 52, y: 51))
        #expect(interaction.selection(on: retina) == nil)
        #expect(harness.changes == 0)

        // At 3 points the box starts.
        interaction.pointerDown(at: CGPoint(x: 50, y: 50), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 53, y: 50))
        // The smallest box is 4 by 4 points (YAZ-2766 row 6).
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 50, y: 50, width: 4, height: 4))
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

    @Test func theHotKeyWithNoBoxDoesNothing() async throws {
        let harness = try await Harness()
        // A fast second press, before a box exists, does not end the capture.
        harness.interaction.key(.hotKey)
        #expect(harness.outcomes.isEmpty)
    }

    @Test func theHotKeyCompletesAnOpenTextAndThenEnds() async throws {
        let harness = try await harnessWithBox()
        let interaction = harness.interaction
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 60, y: 50), on: retina)
        interaction.textChanged("Hi")
        interaction.key(.hotKey)
        #expect(harness.doneResult?.marks.marks.map(\.text) == ["Hi"])
    }

    @Test func aRightClickRemovesTheBoxAndThenCancels() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction
        harness.drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 80, y: 50), on: retina)

        interaction.secondaryClick()
        #expect(interaction.selection(on: retina) == nil)
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
    private func harnessWithBox(
        styles: ToolStyleMemory = ToolStyleMemory(), clipboard: MarkClipboard = MarkClipboard()
    ) async throws -> Harness {
        let harness = try await Harness(styles: styles, clipboard: clipboard)
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
        #expect(interaction.style == MarkStyle(color: .red, size: .thick))
        interaction.selectTool(.rectangle)
        #expect(interaction.tool == nil && interaction.style == nil)
        interaction.selectTool(.rectangle)

        // With a tool and no mark, the handles still show, and a drag in the box draws.
        #expect(interaction.showsHandles)
        #expect(interaction.pointerShape(at: CGPoint(x: 80, y: 50), on: retina) == .crosshair)
        // Outside the box, with no mark, a drag makes a new box (D2, YAZ-2879).
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .crosshair)
        interaction.pointerDown(at: CGPoint(x: 60, y: 30), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 90, y: 50))
        // The mark shows during the drag, but it is in the list only after the release.
        #expect(interaction.visibleMarks.count == 1 && interaction.marks.isEmpty)
        interaction.pointerUp(at: CGPoint(x: 100, y: 60))
        // The points are in the points of the box. The box did not move.
        #expect(interaction.marks.marks == [
            Mark(tool: .rectangle, style: MarkStyle(color: .red, size: .thick), points: [CGPoint(x: 20, y: 10), CGPoint(x: 60, y: 40)]),
        ])
        #expect(harness.rect(on: retina) == boxRect)

        // A drag of less than 3 points draws no mark.
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 61, y: 32), on: retina)
        #expect(interaction.marks.marks.count == 1)
        // With a mark, a drag that starts outside the box does nothing.
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .arrow)
        harness.drag(from: CGPoint(x: 10, y: 5), to: CGPoint(x: 100, y: 60), on: retina)
        harness.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 60), on: plain)
        #expect(interaction.marks.marks.count == 1)
        #expect(harness.rect(on: retina) == boxRect && harness.rect(on: plain) == nil)

        // A mark cannot leave the box: its points stop at the edges, half a line width inside.
        // Thick is 7 points, so the points stop 3.5 points before the edge.
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 900, y: 900), on: retina)
        #expect(interaction.marks.marks.last?.points == [CGPoint(x: 20, y: 10), CGPoint(x: 96.5, y: 56.5)])
        interaction.selectTool(.pen)
        interaction.pointerDown(at: CGPoint(x: 60, y: 30), on: retina)
        for point in [CGPoint(x: 70, y: 40), CGPoint(x: -50, y: 40), CGPoint(x: 90, y: -50), CGPoint(x: 90, y: 500)] {
            interaction.pointerDragged(to: point)
        }
        interaction.pointerUp(at: CGPoint(x: 90, y: 500))
        let pen = try #require(interaction.marks.marks.last)
        #expect(pen.points == [
            CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 20), CGPoint(x: 3.5, y: 20), CGPoint(x: 50, y: 3.5), CGPoint(x: 50, y: 56.5),
        ])
        #expect(interaction.marks.marks.count == 3)

        // With Text, a double-click does not mean Done: a click with Text puts a text (D4, YAZ-2879).
        interaction.selectTool(.text)
        interaction.doubleClick(at: CGPoint(x: 80, y: 50), on: retina)
        #expect(harness.outcomes.isEmpty)

        // With marks and no tool the box is fixed: no handles, no move, no size change, no new box.
        interaction.selectTool(.text)
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
        #expect(interaction.style == MarkStyle(color: .amber, size: .thick))
        interaction.setColor(.green)
        interaction.setSize(.medium)
        interaction.selectTool(.pen)
        #expect(interaction.style == MarkStyle(color: .red, size: .thick))
        interaction.setColor(.blue)
        interaction.selectTool(.highlight)
        #expect(interaction.style == MarkStyle(color: .green, size: .medium))

        // A change of the colour applies to the next mark. It does not change a mark that exists.
        interaction.selectTool(.pen)
        harness.drag(from: CGPoint(x: 50, y: 30), to: CGPoint(x: 90, y: 60), on: retina)
        interaction.setColor(.black)
        interaction.setSize(.thin)
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 100, y: 60), on: retina)
        #expect(interaction.marks.marks.map(\.style) == [
            MarkStyle(color: .blue, size: .thick), MarkStyle(color: .black, size: .thin),
        ])

        // The next capture of the app starts with the same styles.
        let next = try await harnessWithBox(styles: styles)
        next.interaction.selectTool(.pen)
        #expect(next.interaction.style == MarkStyle(color: .black, size: .thin))
        next.interaction.selectTool(.highlight)
        #expect(next.interaction.style == MarkStyle(color: .green, size: .medium))
        next.interaction.selectTool(.ellipse)
        #expect(next.interaction.style == MarkStyle(color: .red, size: .thick))
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
        // (Thick is 24 points, and its line is 30 points). The line breaks at the right edge of the box.
        harness.click(at: CGPoint(x: 60, y: 50), on: retina)
        let edit = try #require(interaction.textEdit)
        #expect(edit.origin == CGPoint(x: 20, y: 15) && edit.wrapWidth == 80 && edit.text.isEmpty)
        #expect(edit.style == MarkStyle(color: .red, size: .thick))
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
            tool: .text, style: MarkStyle(color: .blue, size: .thick), points: [CGPoint(x: 20, y: 15)], text: "One", wrapWidth: 80
        )
        #expect(interaction.marks.marks == [one])

        // A click in a different place completes the text, as in Excalidraw: the Text tool turns
        // off, and "Select" turns on with nothing selected. The click puts no new text (YAZ-3318).
        harness.click(at: CGPoint(x: 50, y: 40), on: retina)
        interaction.textChanged("Two")
        harness.click(at: CGPoint(x: 139, y: 79), on: retina)
        #expect(interaction.marks.marks.count == 2 && interaction.marks.marks.last?.text == "Two")
        #expect(interaction.textEdit == nil && interaction.tool == nil && interaction.isSelecting)
        #expect(interaction.selectedIndex == nil)
        // T starts the next text. Near the right and the bottom edge, the text moves into the box.
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 139, y: 79), on: retina)
        #expect(interaction.textEdit?.origin == CGPoint(x: 52, y: 30))
        #expect(interaction.textEdit?.wrapWidth == 48)

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

    // MARK: The toolbar keys (YAZ-2872)

    /// The scenarios S1 to S17 of the working log YAZ-2873.
    @Test func aToolbarKeyDoesWhatItsButtonDoesButNeverClearsATool() async throws {
        let harness = try await Harness()
        let interaction = harness.interaction

        // S1: no box, no tool.
        interaction.toolbarKey("r")
        #expect(interaction.tool == nil && harness.changes == 0)

        harness.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        // S2 and S3: R selects the Rectangle, and a second R keeps it.
        interaction.toolbarKey("r")
        interaction.toolbarKey("r")
        #expect(interaction.tool == .rectangle)
        // S9: a size key and a colour key change the style of the selected tool.
        interaction.toolbarKey("2")
        interaction.toolbarKey("7")
        #expect(interaction.style == MarkStyle(color: .blue, size: .medium))
        // S5 and S17: a different tool key, and P for the Pen.
        interaction.toolbarKey("o")
        #expect(interaction.tool == .ellipse)
        interaction.toolbarKey("p")
        #expect(interaction.tool == .pen)
        // S18: a key that is not a toolbar key.
        interaction.toolbarKey("q")
        #expect(interaction.tool == .pen)

        // S13: a key during a drag does nothing. The mark keeps its tool.
        interaction.toolbarKey("r")
        interaction.pointerDown(at: CGPoint(x: 60, y: 30), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 90, y: 50))
        interaction.toolbarKey("o")
        interaction.toolbarKey("4")
        interaction.pointerUp(at: CGPoint(x: 100, y: 60))
        #expect(interaction.tool == .rectangle)
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle])
        #expect(interaction.marks.marks[0].style == MarkStyle(color: .blue, size: .medium))

        // S6 and S7: V selects Select, and a second V keeps it.
        interaction.toolbarKey("v")
        interaction.toolbarKey("v")
        #expect(interaction.isSelecting && interaction.tool == nil)
        // S10: with a selected mark, a colour key changes that mark.
        harness.click(at: CGPoint(x: 80, y: 30), on: retina)
        #expect(interaction.selectedIndex == 0)
        interaction.toolbarKey("6")
        #expect(interaction.marks.marks[0].style.color == .green)
        // S8: a tool key releases the mark, as a click on the tool does.
        interaction.toolbarKey("t")
        #expect(interaction.tool == .text && interaction.selectedIndex == nil)

        // S11: while a text is open, the keys are for the typing.
        harness.click(at: CGPoint(x: 100, y: 70), on: retina)
        #expect(interaction.textEdit != nil)
        interaction.toolbarKey("r")
        interaction.toolbarKey("4")
        #expect(interaction.tool == .text && interaction.textEdit?.style.color == .red)
        interaction.completeText()

        // S12: with no tool, no mark and no text, a size or colour key does nothing.
        interaction.selectTool(.text)
        #expect(interaction.tool == nil && interaction.style == nil)
        let changes = harness.changes
        interaction.toolbarKey("2")
        interaction.toolbarKey("5")
        #expect(harness.changes == changes)
        #expect(harness.outcomes.isEmpty)
    }

    /// S23: the keys come from the store. A key that the user changed works, and the old key does not.
    @Test func theToolbarKeysComeFromTheStore() async throws {
        let defaults = MemoryDefaults()
        defaults.set(["tool.rectangle": "q"], forKey: "toolbarKeys")
        let harness = try await Harness(toolbarKeys: ToolbarKeys(defaults: defaults))
        let interaction = harness.interaction
        harness.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        interaction.toolbarKey("r")
        #expect(interaction.tool == nil)
        interaction.toolbarKey("q")
        #expect(interaction.tool == .rectangle)
    }

    // MARK: The start tool (YAZ-2879)

    /// The scenarios S1, S3 to S8, S11, S12, S19 and S20 of the working log YAZ-2880.
    @Test func theStartToolIsOnWhenABoxAppearsAndADragOutsideMakesANewBox() async throws {
        let harness = try await Harness(startTool: .rectangle)
        let interaction = harness.interaction

        // S1: no tool before the box. The Rectangle turns on when the box appears.
        #expect(interaction.tool == nil)
        harness.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        #expect(interaction.tool == .rectangle && interaction.showsToolbar(on: retina) && interaction.showsHandles)

        // S7 and S4: outside the box the pointer is a crosshair, and a drag makes a new box. The tool stays.
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .crosshair)
        harness.drag(from: CGPoint(x: 150, y: 10), to: CGPoint(x: 190, y: 90), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 150, y: 10, width: 40, height: 80))
        #expect(interaction.tool == .rectangle)
        // S19: a drag on the other screen makes a new box there.
        harness.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 70), on: plain)
        #expect(harness.rect(on: plain) == CGRect(x: 10, y: 10, width: 100, height: 60))
        #expect(harness.rect(on: retina) == nil && interaction.tool == .rectangle)

        // S5: the user turns the tool off. A new box keeps no tool.
        interaction.selectTool(.rectangle)
        harness.drag(from: CGPoint(x: 120, y: 80), to: CGPoint(x: 160, y: 120), on: plain)
        #expect(harness.rect(on: plain) == CGRect(x: 120, y: 80, width: 40, height: 40) && interaction.tool == nil)

        // S11 and S12: a right-click removes the box. The next box gets the start tool again.
        interaction.secondaryClick()
        #expect(harness.rect(on: plain) == nil && interaction.tool == nil)
        harness.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        #expect(interaction.tool == .rectangle)

        // S20: an empty text that is open closes, and a drag outside makes a new box.
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 60, y: 30), on: retina)
        #expect(interaction.textEdit != nil)
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .arrow)
        harness.drag(from: CGPoint(x: 150, y: 10), to: CGPoint(x: 190, y: 90), on: retina)
        #expect(interaction.textEdit == nil && interaction.marks.isEmpty)
        #expect(harness.rect(on: retina) == CGRect(x: 150, y: 10, width: 40, height: 80))

        // S3, S6 and S8: a drag in the box draws. With a mark, a drag outside does nothing.
        interaction.selectTool(.rectangle)
        harness.drag(from: CGPoint(x: 155, y: 20), to: CGPoint(x: 185, y: 60), on: retina)
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle])
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .arrow)
        harness.drag(from: CGPoint(x: 10, y: 5), to: CGPoint(x: 100, y: 60), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 150, y: 10, width: 40, height: 80))
        #expect(interaction.marks.marks.count == 1 && harness.outcomes.isEmpty)
    }

    /// S2: a click on a window gives the box and the start tool. S16: "None" works as before.
    @Test func aWindowClickGetsTheStartToolAndNoneKeepsTheOldRules() async throws {
        let withTool = try await Harness(windows: [retina: [front, back]], startTool: .ellipse)
        withTool.drag(from: CGPoint(x: 150, y: 80), to: CGPoint(x: 151, y: 81), on: retina)
        #expect(withTool.rect(on: retina) == back && withTool.interaction.tool == .ellipse)

        let none = try await Harness()
        none.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        #expect(none.interaction.tool == nil)
        // With no tool, a drag in the box moves it.
        none.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 70, y: 40), on: retina)
        #expect(none.rect(on: retina) == CGRect(x: 50, y: 30, width: 100, height: 60))
    }

    /// S13 to S15 (D4): a double-click finishes with no tool and with a drag tool, not with Select,
    /// Text or Number.
    @Test func aDoubleClickFinishesWithADragToolButNotWithSelectTextOrNumber() async throws {
        let inBox = CGPoint(x: 80, y: 50)
        for tool in [Tool.rectangle, .ellipse, .arrow, .pen, .highlight] {
            let harness = try await harnessWithBox()
            harness.interaction.selectTool(tool)
            harness.interaction.doubleClick(at: inBox, on: retina)
            #expect(harness.doneSelection?.rect == boxRect, "\(tool)")
        }
        for tool in [Tool.text, .number] {
            let harness = try await harnessWithBox()
            harness.interaction.selectTool(tool)
            harness.interaction.doubleClick(at: inBox, on: retina)
            #expect(harness.outcomes.isEmpty, "\(tool)")
        }
        let select = try await harnessWithBox()
        select.interaction.toggleSelecting()
        select.interaction.doubleClick(at: inBox, on: retina)
        #expect(select.outcomes.isEmpty)
    }

    // MARK: Select a mark (YAZ-2782)

    /// The box of 100 by 60 points (x 40 to 140, y 20 to 80) with two Thick marks, and "Select" selected.
    /// Mark 0 is a rectangle, x 20 to 60 and y 10 to 40 of the box. Mark 1 is a pen line at y 50
    /// of the box, from x 10 to x 90. Near y 45 of the box, a click is near both lines.
    private func harnessWithMarks(
        styles: ToolStyleMemory = ToolStyleMemory(), clipboard: MarkClipboard = MarkClipboard()
    ) async throws -> Harness {
        let harness = try await harnessWithBox(styles: styles, clipboard: clipboard)
        let interaction = harness.interaction
        interaction.selectTool(.rectangle)
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 100, y: 60), on: retina)
        // After a mark is drawn, the drawing tool stays selected. The app does not change to "Select" (row 4).
        #expect(interaction.tool == .rectangle && !interaction.isSelecting && interaction.selectedIndex == nil)
        interaction.selectTool(.pen)
        harness.drag(from: CGPoint(x: 50, y: 70), to: CGPoint(x: 130, y: 70), on: retina)
        interaction.toggleSelecting()
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle, .pen])
        return harness
    }

    private let rectanglePoints = [CGPoint(x: 20, y: 10), CGPoint(x: 60, y: 40)]

    @Test func withSelectAClickSelectsAMarkAndAClickOnAnEmptyPlaceClearsTheSelection() async throws {
        let harness = try await harnessWithMarks()
        let interaction = harness.interaction
        let marks = interaction.marks

        // "Select" is selected, and no drawing tool. With no selected mark, the sizes and the
        // colours do not show (row 3), and a colour has no target.
        #expect(interaction.isSelecting && interaction.tool == nil)
        #expect(interaction.style == nil && interaction.selectedMark == nil)
        interaction.setColor(.blue)
        #expect(interaction.marks == marks)

        // A click inside the rectangle selects it (row 6). No image is made for a selection.
        let revision = interaction.marksRevision
        var changes = harness.changes
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.selectedIndex == 0 && interaction.selectedMark == marks.marks[0])
        #expect(interaction.style == MarkStyle(color: .red, size: .thick))
        #expect(harness.changes == changes + 1 && interaction.marksRevision == revision)
        // A second click on the selected mark changes nothing.
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.selectedIndex == 0 && harness.changes == changes + 1)

        // On the line of the rectangle, with the tolerance of 6 points: 9.5 points from the middle of a Thick line.
        harness.click(at: CGPoint(x: 51, y: 45), on: retina)
        #expect(interaction.selectedIndex == 0)
        // A handle of the selected mark wins over a mark at the same point: this click is on
        // the bottom handle of the rectangle, and near the pen line. Else that handle takes no drag.
        harness.click(at: CGPoint(x: 80, y: 65), on: retina)
        #expect(interaction.selectedIndex == 0)
        // Two marks at the click, away from a handle: the mark that was drawn last is selected (row 7).
        harness.click(at: CGPoint(x: 70, y: 66), on: retina)
        #expect(interaction.selectedIndex == 1 && interaction.selectedMark?.tool == .pen)

        // The pointer shape: a hand on a mark, resize arrows on a handle of the selected
        // rectangle, and the normal arrow where a drag does nothing.
        #expect(interaction.pointerShape(at: CGPoint(x: 80, y: 45), on: retina) == .openHand)
        #expect(interaction.pointerShape(at: CGPoint(x: 130, y: 40), on: retina) == .arrow)
        #expect(interaction.pointerShape(at: CGPoint(x: 10, y: 5), on: retina) == .arrow)
        #expect(interaction.pointerShape(at: CGPoint(x: 100, y: 30), on: retina) == .openHand)
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.pointerShape(at: CGPoint(x: 100, y: 30), on: retina) == .resize(.topRight))
        #expect(interaction.pointerShape(at: CGPoint(x: 60, y: 45), on: retina) == .resize(.left))

        // A click on an empty place in the box clears the selection (row 8).
        changes = harness.changes
        harness.click(at: CGPoint(x: 130, y: 40), on: retina)
        #expect(interaction.selectedIndex == nil && interaction.style == nil && harness.changes == changes + 1)
        // A click outside the box clears it too.
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        harness.click(at: CGPoint(x: 10, y: 5), on: retina)
        #expect(interaction.selectedIndex == nil)

        // No click changed a mark or the box, and no click is an Undo step.
        #expect(interaction.marks == marks && harness.rect(on: retina) == boxRect)

        // A second click on "Select" clears it, as for a tool (row 2), and the selected mark with it.
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        interaction.toggleSelecting()
        #expect(!interaction.isSelecting && interaction.selectedIndex == nil && interaction.tool == nil)
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.selectedIndex == nil)
        // A drawing tool takes the place of "Select", and "Select" takes the place of a drawing tool.
        interaction.toggleSelecting()
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        interaction.selectTool(.arrow)
        #expect(interaction.tool == .arrow && !interaction.isSelecting && interaction.selectedIndex == nil)
        #expect(interaction.style == MarkStyle(color: .red, size: .thick))
        interaction.toggleSelecting()
        #expect(interaction.tool == nil && interaction.isSelecting)

        // Enter works as before. The result has the marks (row 23).
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        interaction.key(.enter)
        #expect(harness.doneResult?.marks.marks == marks.marks && harness.doneSelection?.rect == boxRect)
    }

    @Test func withSelectADragMovesTheMarkAndNotTheBox() async throws {
        let harness = try await harnessWithMarks()
        let interaction = harness.interaction
        let before = interaction.marks.marks
        #expect(before[0].points == rectanglePoints)

        // A drag of less than 3 points changes nothing. It only selects (row 15).
        harness.drag(from: CGPoint(x: 80, y: 45), to: CGPoint(x: 82, y: 46), on: retina)
        #expect(interaction.selectedIndex == 0 && interaction.marks.marks == before)

        // A drag of the selected mark moves it (row 11). During the drag, the list of marks does
        // not change: the overlay shows the mark of the drag.
        interaction.pointerDown(at: CGPoint(x: 80, y: 45), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 90, y: 50))
        let moving = [CGPoint(x: 30, y: 15), CGPoint(x: 70, y: 45)]
        #expect(interaction.marks.marks == before)
        #expect(interaction.visibleMarks.map(\.points) == [moving, before[1].points])
        #expect(interaction.selectedMark?.points == moving)
        #expect(interaction.pointerShape(at: CGPoint(x: 90, y: 50), on: retina) == .closedHand)
        interaction.pointerDragged(to: CGPoint(x: 95, y: 52))
        interaction.pointerUp(at: CGPoint(x: 100, y: 55))
        let moved = [CGPoint(x: 40, y: 20), CGPoint(x: 80, y: 50)]
        #expect(interaction.marks.marks.map(\.points) == [moved, before[1].points])
        #expect(interaction.marks.marks[0].style == before[0].style && interaction.selectedIndex == 0)
        // The box did not move (row 24).
        #expect(harness.rect(on: retina) == boxRect)

        // One drag is one Undo step (row 21). Undo takes the move back, and Redo puts it back (row 20).
        interaction.undo()
        #expect(interaction.marks.marks == before && interaction.selectedIndex == nil)
        interaction.redo()
        #expect(interaction.marks.marks.map(\.points) == [moved, before[1].points])
        interaction.undo()
        interaction.undo() // the pen line
        #expect(interaction.marks.marks == [before[0]])
        interaction.redo()
        #expect(interaction.marks.marks == before)

        // A drag that starts on a mark that is not selected selects it and moves it in one step (row 11).
        #expect(interaction.selectedIndex == nil)
        harness.drag(from: CGPoint(x: 120, y: 70), to: CGPoint(x: 115, y: 60), on: retina)
        #expect(interaction.selectedIndex == 1)
        #expect(interaction.marks.marks[1].points == [CGPoint(x: 5, y: 40), CGPoint(x: 85, y: 40)])
        #expect(interaction.marks.marks[0] == before[0])

        // A mark cannot leave the box: the move stops when its bounds touch an edge (row 12).
        // The line is 7 points, so its middle stops 3.5 points before the edge.
        harness.drag(from: CGPoint(x: 80, y: 45), to: CGPoint(x: 900, y: 900), on: retina)
        #expect(interaction.marks.marks[0].points == [CGPoint(x: 56.5, y: 26.5), CGPoint(x: 96.5, y: 56.5)])
        // The drag starts on the bottom line of the rectangle, between two of its handles.
        harness.drag(from: CGPoint(x: 110, y: 76.5), to: CGPoint(x: -900, y: -900), on: retina)
        #expect(interaction.marks.marks[0].points == [CGPoint(x: 3.5, y: 3.5), CGPoint(x: 43.5, y: 33.5)])

        // With "Select", the box is still fixed while marks exist (row 24): a drag on an empty
        // place, on a corner of the box, outside the box and on a different screen changes nothing.
        let marks = interaction.marks
        #expect(!interaction.showsHandles)
        harness.drag(from: CGPoint(x: 130, y: 30), to: CGPoint(x: 100, y: 50), on: retina)
        harness.drag(from: CGPoint(x: 140, y: 80), to: CGPoint(x: 180, y: 95), on: retina)
        harness.drag(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 30, y: 15), on: retina)
        harness.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 60), on: plain)
        #expect(harness.rect(on: retina) == boxRect && harness.rect(on: plain) == nil && interaction.marks == marks)
        // A right-click does nothing while marks exist (row 26), also during a drag of a mark.
        interaction.secondaryClick()
        interaction.pointerDown(at: CGPoint(x: 60, y: 40), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 80, y: 50))
        interaction.secondaryClick()
        interaction.pointerUp(at: CGPoint(x: 80, y: 50))
        #expect(interaction.marks.marks[0].points == [CGPoint(x: 23.5, y: 13.5), CGPoint(x: 63.5, y: 43.5)])
        #expect(harness.rect(on: retina) == boxRect && harness.outcomes.isEmpty && interaction.isSelecting)
    }

    @Test func withSelectAndNoMarkTheBoxMovesAndChangesItsSize() async throws {
        // Row 25: as when no tool is selected.
        let harness = try await harnessWithBox()
        let interaction = harness.interaction
        interaction.toggleSelecting()
        #expect(interaction.isSelecting && interaction.showsHandles && interaction.style == nil)
        #expect(interaction.pointerShape(at: CGPoint(x: 80, y: 45), on: retina) == .openHand)
        #expect(interaction.pointerShape(at: CGPoint(x: 140, y: 80), on: retina) == .resize(.bottomRight))
        harness.drag(from: CGPoint(x: 80, y: 45), to: CGPoint(x: 90, y: 50), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 50, y: 25, width: 100, height: 60))
        harness.drag(from: CGPoint(x: 150, y: 85), to: CGPoint(x: 160, y: 90), on: retina)
        #expect(harness.rect(on: retina) == CGRect(x: 50, y: 25, width: 110, height: 65))
        // A double-click does not mean Done, as with a tool (YAZ-2767 row 27).
        interaction.doubleClick(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(harness.outcomes.isEmpty)
        // A right-click removes the box, and "Select" with it (row 26, with no mark).
        interaction.secondaryClick()
        #expect(harness.rect(on: retina) == nil && !interaction.isSelecting && harness.outcomes.isEmpty)
        // With no box, "Select" cannot be selected, as a tool.
        interaction.toggleSelecting()
        #expect(!interaction.isSelecting)
    }

    @Test func aDragOfAHandleChangesARectangleAndAnEndOfAnArrow() async throws {
        let harness = try await harnessWithMarks()
        let interaction = harness.interaction
        // A third mark: an arrow in the top-right part of the box, from 75, 10 to 90, 30 of the box.
        interaction.selectTool(.arrow)
        harness.drag(from: CGPoint(x: 115, y: 30), to: CGPoint(x: 130, y: 50), on: retina)
        interaction.toggleSelecting()
        let before = interaction.marks.marks

        // Only the selected mark has handles. With no selected mark, a drag from the corner of
        // the rectangle selects the rectangle and moves it. Its size stays.
        #expect(interaction.selectedMark == nil)
        harness.drag(from: CGPoint(x: 100, y: 60), to: CGPoint(x: 110, y: 65), on: retina)
        #expect(interaction.marks.marks[0].frame == CGRect(x: 30, y: 15, width: 40, height: 30))
        interaction.undo()
        // A selected Rectangle has eight handles (row 10).
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.selectedMark?.handles.count == 8)

        // A drag of a corner handle changes two edges (row 13). The pointer took the handle
        // 1 point from its middle, and the corner keeps that distance.
        interaction.pointerDown(at: CGPoint(x: 101, y: 61), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 111, y: 66))
        #expect(interaction.pointerShape(at: CGPoint(x: 111, y: 66), on: retina) == .resize(.bottomRight))
        #expect(interaction.marks.marks == before && interaction.selectedMark?.frame == CGRect(x: 20, y: 10, width: 50, height: 35))
        interaction.pointerUp(at: CGPoint(x: 121, y: 71))
        #expect(interaction.marks.marks[0].frame == CGRect(x: 20, y: 10, width: 60, height: 40))
        #expect(interaction.marks.marks[0].style == before[0].style && interaction.selectedIndex == 0)
        // An edge handle changes one edge. It stops in the box, half a line width before the edge.
        harness.drag(from: CGPoint(x: 60, y: 50), to: CGPoint(x: -900, y: 900), on: retina)
        #expect(interaction.marks.marks[0].frame == CGRect(x: 3.5, y: 10, width: 76.5, height: 40))
        // Through the opposite edge the rectangle turns over (YAZ-2766 row 5).
        harness.drag(from: CGPoint(x: 80, y: 30), to: CGPoint(x: 80, y: 75), on: retina)
        #expect(interaction.marks.marks[0].frame == CGRect(x: 3.5, y: 50, width: 76.5, height: 5))
        // A drag of a handle of less than 3 points changes nothing.
        harness.drag(from: CGPoint(x: 120, y: 75), to: CGPoint(x: 121, y: 76), on: retina)
        #expect(interaction.marks.marks[0].frame == CGRect(x: 3.5, y: 50, width: 76.5, height: 5))
        // Each drag is one Undo step.
        interaction.undo()
        interaction.undo()
        #expect(interaction.marks.marks[0].frame == CGRect(x: 20, y: 10, width: 60, height: 40))
        interaction.undo()
        #expect(interaction.marks.marks == before)

        // A selected Arrow has one handle at each end (row 10). A drag of the end with the head
        // moves that end, and the other end stays (row 14).
        harness.click(at: CGPoint(x: 122, y: 40), on: retina)
        #expect(interaction.selectedIndex == 2 && interaction.selectedMark?.handles.map(\.key) == [.end(0), .end(1)])
        #expect(interaction.pointerShape(at: CGPoint(x: 130, y: 50), on: retina) == .crosshair)
        harness.drag(from: CGPoint(x: 130, y: 50), to: CGPoint(x: 100, y: 40), on: retina)
        #expect(interaction.marks.marks[2].points == [CGPoint(x: 75, y: 10), CGPoint(x: 60, y: 20)])
        harness.drag(from: CGPoint(x: 115, y: 30), to: CGPoint(x: 900, y: -900), on: retina)
        #expect(interaction.marks.marks[2].points == [CGPoint(x: 96.5, y: 3.5), CGPoint(x: 60, y: 20)])
        #expect(interaction.marks.marks[2].style == before[2].style)

        // A selected Pen mark has no handle. It only moves.
        harness.click(at: CGPoint(x: 60, y: 70), on: retina)
        #expect(interaction.selectedIndex == 1 && interaction.selectedMark?.handles.isEmpty == true)
        harness.drag(from: CGPoint(x: 50, y: 70), to: CGPoint(x: 60, y: 65), on: retina)
        #expect(interaction.marks.marks[1].points == [CGPoint(x: 16.5, y: 45), CGPoint(x: 96.5, y: 45)])
    }

    @MainActor @Test func deleteAndAStyleChangeApplyToTheSelectedMark() async throws {
        let styles = ToolStyleMemory()
        let harness = try await harnessWithMarks(styles: styles)
        let interaction = harness.interaction
        // A third mark: the text "Hi" in the top-right part of the box.
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 115, y: 40), on: retina)
        interaction.textChanged("Hi")
        interaction.completeText()
        interaction.toggleSelecting()
        let before = interaction.marks.marks
        #expect(before.map(\.tool) == [.rectangle, .pen, .text])

        // A click on a colour button changes the selected mark (row 17). It is one Undo step.
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        var revision = interaction.marksRevision
        interaction.setColor(.blue)
        #expect(interaction.marks.marks[0].style == MarkStyle(color: .blue, size: .thick))
        #expect(interaction.marks.marks[0].points == rectanglePoints && interaction.selectedIndex == 0)
        #expect(interaction.style == MarkStyle(color: .blue, size: .thick) && interaction.marksRevision == revision + 1)
        // The same colour again changes nothing, and it is no Undo step.
        interaction.setColor(.blue)
        #expect(interaction.marksRevision == revision + 1)
        // A size button changes the line.
        interaction.setSize(.thin)
        #expect(interaction.marks.marks[0].style == MarkStyle(color: .blue, size: .thin))
        // The other marks did not change.
        #expect(Array(interaction.marks.marks.dropFirst()) == Array(before.dropFirst()))
        // It also becomes the colour and the size of the next mark of that kind, and only of that kind.
        #expect(styles[.rectangle] == MarkStyle(color: .blue, size: .thin))
        #expect(styles[.pen] == MarkStyle(color: .red, size: .thick) && styles[.ellipse] == MarkStyle(color: .red, size: .thick))

        // Undo takes back the size, and then the colour (row 20). Redo puts them back.
        interaction.undo()
        #expect(interaction.marks.marks[0].style == MarkStyle(color: .blue, size: .thick) && interaction.selectedIndex == nil)
        interaction.undo()
        #expect(interaction.marks.marks == before)
        interaction.redo()
        interaction.redo()
        #expect(interaction.marks.marks[0].style == MarkStyle(color: .blue, size: .thin))

        // For a Text mark, a size button changes the font size (row 18).
        harness.click(at: CGPoint(x: 120, y: 40), on: retina)
        #expect(interaction.selectedIndex == 2 && interaction.style?.fontSize == 24)
        interaction.setSize(.thin)
        #expect(interaction.marks.marks[2].style.fontSize == 14 && interaction.marks.marks[2].text == "Hi")
        #expect(styles[.text] == MarkStyle(color: .red, size: .thin))

        // Only one attribute changes in the style of the next mark: the pen line is green and
        // Thick, and the next pen line is green with the size that the tool had.
        styles[.pen] = MarkStyle(color: .black, size: .medium)
        harness.click(at: CGPoint(x: 60, y: 70), on: retina)
        interaction.setColor(.green)
        #expect(interaction.marks.marks[1].style == MarkStyle(color: .green, size: .thick))
        #expect(styles[.pen] == MarkStyle(color: .green, size: .medium))

        // A thicker line stays in the box: this Thin rectangle touches the left edge, and with
        // Thick its middle is 3.5 points inside.
        harness.drag(from: CGPoint(x: 80, y: 45), to: CGPoint(x: -900, y: 45), on: retina)
        #expect(interaction.marks.marks[0].frame == CGRect(x: 1, y: 10, width: 40, height: 30))
        interaction.setSize(.thick)
        #expect(interaction.marks.marks[0].frame == CGRect(x: 3.5, y: 10, width: 40, height: 30))

        // Delete removes the selected mark (row 16). Undo puts it back, at its place in the order.
        let three = interaction.marks.marks
        revision = interaction.marksRevision
        interaction.key(.delete)
        #expect(interaction.marks.marks == Array(three.dropFirst()) && interaction.selectedIndex == nil)
        #expect(interaction.marksRevision == revision + 1 && interaction.style == nil)
        // Delete with no selected mark does nothing.
        interaction.key(.delete)
        #expect(interaction.marks.marks.count == 2)
        interaction.undo()
        #expect(interaction.marks.marks == three)
        interaction.redo()
        #expect(interaction.marks.marks == Array(three.dropFirst()))

        // The last mark is deleted: the box is free again, as after Undo of the last mark, and
        // Undo still puts the mark back.
        harness.click(at: CGPoint(x: 60, y: 70), on: retina)
        interaction.deleteSelectedMark()
        harness.click(at: CGPoint(x: 98, y: 32), on: retina)
        #expect(interaction.selectedIndex == 0)
        interaction.key(.delete)
        #expect(interaction.marks.isEmpty && interaction.showsHandles && interaction.canUndo)
        interaction.undo()
        #expect(interaction.marks.marks.map(\.tool) == [.text] && !interaction.showsHandles)
        // A change of the box clears Undo and Redo: those marks belong to the old box.
        interaction.redo()
        harness.drag(from: CGPoint(x: 80, y: 45), to: CGPoint(x: 90, y: 45), on: retina)
        #expect(harness.rect(on: retina) == boxRect.offsetBy(dx: 10, dy: 0))
        interaction.undo()
        #expect(interaction.marks.isEmpty && !interaction.canUndo)
    }

    // MARK: Number (YAZ-2841)

    /// Rows 1.2 to 1.5, 1.7 to 1.9, 1.17 and 1.18: a pointer down in the box puts the next number at once.
    @Test func withNumberAClickPutsTheNextNumberAtOnce() async throws {
        let styles = ToolStyleMemory()
        let harness = try await harnessWithBox(styles: styles)
        let interaction = harness.interaction
        interaction.selectTool(.number)
        #expect(interaction.tool == .number && interaction.style == MarkStyle(color: .red, size: .thick))
        #expect(interaction.pointerShape(at: CGPoint(x: 90, y: 50), on: retina) == .crosshair)

        // The pointer down puts number 1 at once. No drag and no release are necessary.
        let revision = interaction.marksRevision
        interaction.pointerDown(at: CGPoint(x: 90, y: 50), on: retina)
        let one = Mark(tool: .number, style: MarkStyle(color: .red, size: .thick), points: [CGPoint(x: 50, y: 30)], number: 1)
        #expect(interaction.marks.marks == [one] && interaction.marksRevision == revision + 1 && interaction.canUndo)
        // A drag after it does nothing more: no second mark, no move, and the box stays.
        interaction.pointerDragged(to: CGPoint(x: 120, y: 70))
        interaction.pointerUp(at: CGPoint(x: 120, y: 70))
        #expect(interaction.marks.marks == [one] && interaction.visibleMarks == [one])
        #expect(harness.rect(on: retina) == boxRect)

        // The second click puts number 2. Near the top-left corner, the middle stays half a
        // circle (20 points) inside the box, so the full circle shows.
        harness.click(at: CGPoint(x: 41, y: 21), on: retina)
        #expect(interaction.marks.marks.map(\.number) == [1, 2])
        #expect(interaction.marks.marks.last?.points == [CGPoint(x: 20, y: 20)])
        // A click outside the box, or on the other screen, puts nothing.
        harness.click(at: CGPoint(x: 10, y: 5), on: retina)
        harness.click(at: CGPoint(x: 150, y: 50), on: retina)
        harness.click(at: CGPoint(x: 10, y: 10), on: plain)
        #expect(interaction.marks.marks.count == 2)

        // A fast double-click, as the view sends it: each pointer down puts a number, and the
        // double-click does not mean Done while a tool is on.
        let place = CGPoint(x: 120, y: 60)
        interaction.pointerDown(at: place, on: retina)
        interaction.pointerUp(at: place)
        interaction.pointerDown(at: place, on: retina)
        interaction.doubleClick(at: place, on: retina)
        interaction.pointerUp(at: place)
        #expect(interaction.marks.marks.map(\.number) == [1, 2, 3, 4] && harness.outcomes.isEmpty)

        // One click is one Undo step. After Undo of 4, the next number is 4 again.
        interaction.undo()
        #expect(interaction.marks.marks.map(\.number) == [1, 2, 3] && interaction.marks.nextNumber == 4)
        interaction.redo()
        interaction.undo()

        // The numbers hold the box, as each mark: no handles, and a right-click does nothing.
        #expect(!interaction.showsHandles)
        interaction.secondaryClick()
        #expect(harness.rect(on: retina) == boxRect && harness.outcomes.isEmpty && interaction.marks.marks.count == 3)

        // A new colour and size apply to the next number. The numbers that exist do not change.
        interaction.setColor(.blue)
        interaction.setSize(.medium)
        harness.click(at: CGPoint(x: 70, y: 40), on: retina)
        let four = Mark(tool: .number, style: MarkStyle(color: .blue, size: .medium), points: [CGPoint(x: 30, y: 20)], number: 4)
        #expect(interaction.marks.marks.last == four)
        #expect(interaction.marks.marks.dropLast().allSatisfy { $0.style == MarkStyle(color: .red, size: .thick) })

        // A new capture starts at 1. Number keeps its last colour and size while the app runs.
        let next = try await harnessWithBox(styles: styles)
        next.interaction.selectTool(.number)
        #expect(next.interaction.style == MarkStyle(color: .blue, size: .medium))
        next.click(at: CGPoint(x: 90, y: 50), on: retina)
        #expect(next.interaction.marks.marks.map(\.number) == [1])

        // Enter: the result has the four numbers.
        interaction.key(.enter)
        #expect(harness.doneResult?.marks.marks.map(\.number) == [1, 2, 3, 4])
    }

    /// Rows 1.12 to 1.14 and 1.16: Select moves a number, changes its style, and deletes it.
    /// Its number never changes.
    @Test func withSelectANumberMovesChangesItsStyleAndIsDeleted() async throws {
        let styles = ToolStyleMemory()
        let harness = try await harnessWithBox(styles: styles)
        let interaction = harness.interaction
        interaction.selectTool(.number)
        // Numbers 1, 2 and 3, Thick, at x 20, 50 and 80 of the box, and y 30.
        for x: CGFloat in [60, 90, 120] {
            harness.click(at: CGPoint(x: x, y: 50), on: retina)
        }
        let before = interaction.marks.marks
        #expect(before.map(\.number) == [1, 2, 3])
        interaction.toggleSelecting()

        // A click 6 points above the circle of number 2 selects it. Higher, it does not.
        harness.click(at: CGPoint(x: 90, y: 50 - 20 - 7), on: retina)
        #expect(interaction.selectedIndex == nil)
        harness.click(at: CGPoint(x: 90, y: 50 - 20 - 6), on: retina)
        #expect(interaction.selectedIndex == 1 && interaction.selectedMark?.handles.isEmpty == true)
        #expect(interaction.pointerShape(at: CGPoint(x: 90, y: 50), on: retina) == .openHand)

        // A drag moves it. The move stops when the circle touches the bottom edge of the box.
        harness.drag(from: CGPoint(x: 90, y: 50), to: CGPoint(x: 90, y: 900), on: retina)
        #expect(interaction.marks.marks[1].points == [CGPoint(x: 50, y: 40)] && interaction.marks.marks[1].number == 2)
        #expect(interaction.selectedIndex == 1 && harness.rect(on: retina) == boxRect)

        // A size and a colour change the selected number. Its number does not change.
        interaction.setSize(.thin)
        interaction.setColor(.green)
        let green = Mark(tool: .number, style: MarkStyle(color: .green, size: .thin), points: [CGPoint(x: 50, y: 40)], number: 2)
        #expect(interaction.marks.marks[1] == green)
        #expect(styles[.number] == MarkStyle(color: .green, size: .thin))
        // A larger circle stays in the box: the Thin number goes to the bottom edge, then it gets Thick.
        harness.drag(from: CGPoint(x: 90, y: 60), to: CGPoint(x: 90, y: 900), on: retina)
        #expect(interaction.marks.marks[1].points == [CGPoint(x: 50, y: 49)])
        interaction.setSize(.thick)
        #expect(interaction.marks.marks[1].points == [CGPoint(x: 50, y: 40)] && interaction.marks.marks[1].number == 2)
        #expect(interaction.marks.marks[1].bounds.maxY == 60)
        // The other numbers did not change.
        #expect(interaction.marks.marks[0] == before[0] && interaction.marks.marks[2] == before[2])

        // Esc clears the selection first, and the capture stays open.
        interaction.key(.escape)
        #expect(interaction.selectedIndex == nil && harness.outcomes.isEmpty)

        // Delete removes the selected number. The other numbers keep their numbers.
        harness.click(at: CGPoint(x: 90, y: 60), on: retina)
        #expect(interaction.selectedIndex == 1)
        interaction.key(.delete)
        #expect(interaction.marks.marks == [before[0], before[2]] && interaction.marks.nextNumber == 4)
        interaction.undo()
        #expect(interaction.marks.marks.map(\.number) == [1, 2, 3])
        // With no selection, Esc cancels the capture.
        interaction.key(.escape)
        #expect(harness.isCancelled)
    }

    @Test func escClearsTheSelectionFirstAndCancelsTheCaptureTheSecondTime() async throws {
        // Row 22.
        let harness = try await harnessWithMarks()
        let interaction = harness.interaction
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.selectedIndex == 0)
        let changes = harness.changes
        interaction.key(.escape)
        #expect(interaction.selectedIndex == nil && harness.outcomes.isEmpty && harness.changes == changes + 1)
        #expect(interaction.isSelecting && interaction.marks.marks.count == 2)
        interaction.key(.escape)
        #expect(harness.isCancelled)
    }

    @MainActor @Test func aDoubleClickOnATextMarkOpensItsTextAgain() async throws {
        let harness = try await harnessWithMarks()
        let interaction = harness.interaction
        // A third mark: the text "One", Thick, at 75, 5 of the box.
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 115, y: 40), on: retina)
        interaction.textChanged("One")
        interaction.completeText()
        interaction.toggleSelecting()
        let one = try #require(interaction.marks.marks.last)
        #expect(one.points == [CGPoint(x: 52, y: 5)] && one.wrapWidth == 48)
        let before = interaction.marks.marks
        let onText = CGPoint(x: 100, y: 38)

        /// A double-click, as the view sends it: a click, then a pointer down with the double-click.
        func doubleClick(at point: CGPoint) {
            harness.click(at: point, on: retina)
            interaction.pointerDown(at: point, on: retina)
            interaction.doubleClick(at: point, on: retina)
            interaction.pointerUp(at: point)
        }

        // The text field opens with the old text, at the place and with the style of the mark (row 19).
        doubleClick(at: onText)
        var edit = try #require(interaction.textEdit)
        #expect(edit.text == "One" && edit.origin == one.points[0] && edit.wrapWidth == 48 && edit.style == one.style)
        #expect(edit.index == 2 && interaction.selectedIndex == 2)
        // The text shows in its field, not in the image, and it has no outline. The list is not changed yet.
        #expect(interaction.visibleMarks == Array(before.prefix(2)) && interaction.selectedMark == nil)
        #expect(interaction.marks.marks == before && harness.outcomes.isEmpty)
        // The sizes and the colours show the style of the open text.
        #expect(interaction.style == one.style)

        // Return completes it: the mark has the new text, at the same place in the order. One Undo step.
        interaction.textChanged("One two")
        interaction.setColor(.blue)
        interaction.completeText()
        #expect(interaction.textEdit == nil && interaction.marks.marks.count == 3)
        #expect(interaction.marks.marks[2].text == "One two" && interaction.marks.marks[2].style.color == .blue)
        #expect(interaction.marks.marks[2].points == one.points && interaction.visibleMarks == interaction.marks.marks)
        #expect(interaction.selectedIndex == 2)
        interaction.undo()
        #expect(interaction.marks.marks == before)
        interaction.redo()
        #expect(interaction.marks.marks[2].text == "One two")
        interaction.undo()

        // Esc closes the field and keeps the old text. The mark stays selected, and the capture stays open.
        doubleClick(at: onText)
        interaction.textChanged("gone")
        var revision = interaction.marksRevision
        interaction.key(.escape)
        #expect(interaction.textEdit == nil && interaction.marks.marks == before && interaction.selectedIndex == 2)
        #expect(interaction.marksRevision == revision + 1 && harness.outcomes.isEmpty)

        // A text that did not change is no Undo step: Undo takes back the step before it, the new text "One".
        doubleClick(at: onText)
        interaction.completeText()
        #expect(interaction.marks.marks == before)
        interaction.undo()
        #expect(interaction.marks.marks == Array(before.prefix(2)))
        interaction.redo()

        // A click in a different place completes the text, as for a new text. The click does nothing
        // more: it does not select the rectangle below it, and nothing is selected (YAZ-3318).
        doubleClick(at: onText)
        interaction.textChanged("Two")
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.textEdit == nil && interaction.marks.marks[2].text == "Two" && interaction.selectedIndex == nil)
        #expect(interaction.isSelecting)

        // An empty text removes the mark (row 19). Undo puts it back.
        doubleClick(at: onText)
        edit = try #require(interaction.textEdit)
        #expect(edit.text == "Two")
        interaction.textChanged("  ")
        revision = interaction.marksRevision
        interaction.completeText()
        #expect(interaction.marks.marks == Array(before.prefix(2)) && interaction.selectedIndex == nil)
        #expect(interaction.marksRevision == revision + 1)
        interaction.undo()
        #expect(interaction.marks.marks.last?.text == "Two")

        // A double-click on a mark that is not a text opens no text, and it does not mean Done.
        doubleClick(at: CGPoint(x: 80, y: 45))
        #expect(interaction.textEdit == nil && interaction.selectedIndex == 0 && harness.outcomes.isEmpty)
        // Done while a text is open again: the text is completed first.
        doubleClick(at: onText)
        interaction.textChanged("Last")
        interaction.key(.enter)
        #expect(harness.doneResult?.marks.marks.map(\.text) == ["", "", "Last"])
    }

    /// YAZ-3318: Return selects a new text (D6). Then a digit (D2) and a corner drag (D3) change its
    /// font, and the next text starts with that font (D5). With no selected text, the digits pick a
    /// size and a colour, as before.
    @MainActor @Test func aSelectedTextTakesItsFontFromADigitAndACornerDrag() async throws {
        let styles = ToolStyleMemory()
        let harness = try await harnessWithBox(styles: styles)
        let interaction = harness.interaction
        let boxOrigin = CGPoint(x: boxRect.minX, y: boxRect.minY)

        // Return on an empty text adds no mark, and the Text tool stays on (S32).
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 45, y: 35), on: retina)
        interaction.completeText(selectsNewText: true)
        #expect(interaction.marks.isEmpty && interaction.tool == .text && interaction.selectedIndex == nil)

        // Return completes a new text and selects it, with "Select" on and the Text tool off (S31).
        harness.click(at: CGPoint(x: 45, y: 35), on: retina)
        interaction.textChanged("Hi")
        interaction.completeText(selectsNewText: true)
        let hi = try #require(interaction.marks.marks.first)
        #expect(hi.points == [CGPoint(x: 5, y: 0)] && hi.style.fontSize == 24)
        #expect(interaction.selectedIndex == 0 && interaction.isSelecting && interaction.tool == nil)
        #expect(interaction.selectedMark?.handles.count == 4)

        // A digit sets the font, and the top-left stays (S1). The same digit again is no new step (S2).
        interaction.toolbarKey("1")
        #expect(interaction.marks.marks[0].style.fontSize == 14 && interaction.marks.marks[0].points == hi.points)
        interaction.toolbarKey("1")
        interaction.undo()
        #expect(interaction.marks.marks == [hi])

        // A digit from 4 to 9 sets the font of a selected text, not its colour (S8): 5 is Amber for a
        // different mark, and 40 points here.
        harness.click(at: CGPoint(x: 50, y: 30), on: retina)
        #expect(interaction.selectedIndex == 0)
        interaction.toolbarKey("4")
        #expect(interaction.marks.marks[0].style.fontSize == 40 && interaction.marks.marks[0].style.color == .red)
        interaction.toolbarKey("5")
        #expect(interaction.marks.marks[0].style.fontSize == 56 && interaction.marks.marks[0].style.color == .red)
        interaction.toolbarKey("4")
        #expect(styles[.text].fontSize == 40)

        // A drag of the bottom-right corner to the middle of the diagonal: half the font (S13, S15).
        let forty = interaction.marks.marks[0]
        let handle = try #require(forty.handles.first { $0.key == .frame(.bottomRight) })
        let outline = forty.outline
        // The pointer shows the resize arrow of each corner, and the open hand on the text (S12).
        for corner in forty.handles {
            let onCorner = CGPoint(x: boxOrigin.x + corner.point.x, y: boxOrigin.y + corner.point.y)
            guard case .frame(let key) = corner.key else { continue }
            #expect(interaction.pointerShape(at: onCorner, on: retina) == .resize(key))
        }
        #expect(interaction.pointerShape(at: CGPoint(x: boxOrigin.x + outline.midX, y: boxOrigin.y + outline.midY), on: retina) == .openHand)
        let middle = CGPoint(x: (outline.minX + handle.point.x) / 2, y: (outline.minY + handle.point.y) / 2)
        harness.drag(
            from: CGPoint(x: boxOrigin.x + handle.point.x, y: boxOrigin.y + handle.point.y),
            to: CGPoint(x: boxOrigin.x + middle.x, y: boxOrigin.y + middle.y), on: retina
        )
        #expect(interaction.marks.marks[0].style.fontSize == 20 && interaction.marks.marks[0].points == hi.points)
        // The next text gets the font of the drag too (S26). One drag is one Undo step (S20).
        #expect(styles[.text].fontSize == 20)
        interaction.undo()
        #expect(interaction.marks.marks == [forty])
        interaction.redo()
        #expect(interaction.marks.marks[0].style.fontSize == 20)

        // With no selected text, the digits pick a size and a colour, as before (S5). Redo cleared
        // the selection.
        #expect(interaction.selectedIndex == nil)
        interaction.selectTool(.text)
        interaction.toolbarKey("2")
        interaction.toolbarKey("6")
        #expect(styles[.text] == MarkStyle(color: .green, size: .medium) && interaction.marks.marks.count == 1)

        // A click in a different place completes the text, and does not select it. The Text tool
        // turns off and "Select" turns on, as in Excalidraw (S34).
        harness.click(at: CGPoint(x: 100, y: 40), on: retina)
        interaction.textChanged("Two")
        harness.click(at: CGPoint(x: 60, y: 60), on: retina)
        #expect(interaction.marks.marks.count == 2 && interaction.selectedIndex == nil)
        #expect(interaction.tool == nil && interaction.isSelecting && interaction.textEdit == nil)
        #expect(interaction.marks.marks[1].style.fontSize == 18)
    }

    /// YAZ-3318: a digit on a mark that is not text keeps its old action (S3). A digit that Settings
    /// gave to an action still sets the font of a selected text (S9). A corner drag changes only
    /// the font of the next text, not its colour (D5). A text that was opened again stays selected
    /// after Return (S36).
    @MainActor @Test func aDigitOnADifferentMarkAKeyFromSettingsAndAReopenedText() async throws {
        let defaults = MemoryDefaults()
        defaults.set(["select": "1", "size.thin": "v"], forKey: "toolbarKeys")
        let styles = ToolStyleMemory()
        let harness = try await Harness(styles: styles, toolbarKeys: ToolbarKeys(defaults: defaults))
        let interaction = harness.interaction
        harness.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        interaction.selectTool(.rectangle)
        harness.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 100, y: 60), on: retina)
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 115, y: 40), on: retina)
        interaction.textChanged("Hi")
        interaction.completeText(selectsNewText: true)
        #expect(interaction.selectedIndex == 1 && interaction.marks.marks[1].points == [CGPoint(x: 52, y: 5)])

        // S9: 1 is the key of Select now, but with a text selected it gives 14 points.
        interaction.toolbarKey("1")
        #expect(interaction.marks.marks[1].style.fontSize == 14 && interaction.isSelecting)

        // S3: with the rectangle selected, 2 is Medium and 7 is Blue, as before.
        harness.click(at: CGPoint(x: 60, y: 45), on: retina)
        #expect(interaction.selectedIndex == 0)
        interaction.toolbarKey("2")
        interaction.toolbarKey("7")
        #expect(interaction.marks.marks[0].style == MarkStyle(color: .blue, size: .medium))

        // D5: the next text is green. A corner drag of the red text changes only the font of the next text.
        interaction.selectTool(.text)
        interaction.toolbarKey("6")
        #expect(styles[.text].color == .green && styles[.text].fontSize == 14)
        interaction.toggleSelecting()
        harness.click(at: CGPoint(x: 95, y: 30), on: retina)
        let small = try #require(interaction.selectedMark)
        #expect(small.tool == .text)
        let outline = small.outline
        let far = CGPoint(x: outline.minX + outline.width * 2, y: outline.minY + outline.height * 2)
        harness.drag(
            from: CGPoint(x: 40 + outline.maxX, y: 20 + outline.maxY), to: CGPoint(x: 40 + far.x, y: 20 + far.y), on: retina
        )
        #expect(interaction.marks.marks[1].style.fontSize == 28 && interaction.marks.marks[1].style.color == .red)
        #expect(styles[.text].color == .green && styles[.text].fontSize == 28)

        // S36: a double-click opens the text again. Return completes it, and it stays selected.
        let onText = CGPoint(x: 100, y: 35)
        harness.click(at: onText, on: retina)
        interaction.pointerDown(at: onText, on: retina)
        interaction.doubleClick(at: onText, on: retina)
        interaction.pointerUp(at: onText)
        #expect(interaction.textEdit?.index == 1)
        interaction.textChanged("Hi there")
        interaction.completeText(selectsNewText: true)
        #expect(interaction.selectedIndex == 1 && interaction.isSelecting && interaction.marks.marks[1].text == "Hi there")
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
        #expect(harness.rect(on: retina) == nil && harness.rect(on: plain) == nil && harness.outcomes.isEmpty)

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

    // MARK: Copy, cut and paste (YAZ-3148)

    // The rows are the scenarios on the working log YAZ-3150.

    @Test func aPasteIsASelectedCopy16PointsFurtherAndACutIsOneUndoStep() async throws {
        let harness = try await harnessWithMarks()
        let interaction = harness.interaction
        // Nothing was copied, and no mark is selected: nothing happens (rows 2 and 16).
        interaction.key(.paste)
        interaction.key(.copy)
        interaction.key(.paste)
        #expect(interaction.marks.marks.count == 2)

        // A copy of the selected rectangle changes no mark and makes no Undo step (row 1).
        harness.click(at: CGPoint(x: 80, y: 45), on: retina)
        #expect(interaction.selectedIndex == 0)
        let revision = interaction.marksRevision
        interaction.key(.copy)
        #expect(interaction.marks.marks.count == 2 && interaction.marksRevision == revision)

        // A paste with a drawing tool on: the copy goes on top, 16 points to the right and down.
        // It is selected, "Select" is on, and the tool is off (rows 10 and 14).
        interaction.selectTool(.arrow)
        interaction.key(.paste)
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle, .pen, .rectangle])
        #expect(interaction.marks.marks[2].points == [CGPoint(x: 36, y: 26), CGPoint(x: 76, y: 56)])
        #expect(interaction.selectedIndex == 2 && interaction.isSelecting && interaction.tool == nil)
        #expect(interaction.style == interaction.marks.marks[0].style)

        // A drag right after the paste moves the copy (row 15).
        harness.drag(from: CGPoint(x: 106, y: 68), to: CGPoint(x: 100, y: 62), on: retina)
        #expect(interaction.marks.marks[2].points == [CGPoint(x: 30, y: 20), CGPoint(x: 70, y: 50)])

        // Undo takes back the move, then the paste. No mark is selected. Redo brings the copy back (row 27).
        interaction.key(.undo)
        interaction.key(.undo)
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle, .pen] && interaction.selectedIndex == nil)
        interaction.key(.redo)
        #expect(interaction.marks.marks.count == 3 && interaction.selectedIndex == nil)

        // A cut of the pen line is one Undo step. The first paste after it is at the same place (rows 7 and 12).
        harness.click(at: CGPoint(x: 60, y: 70), on: retina)
        #expect(interaction.selectedIndex == 1)
        let pen = interaction.marks.marks[1]
        interaction.key(.cut)
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle, .rectangle] && interaction.selectedIndex == nil)
        interaction.key(.paste)
        #expect(interaction.marks.marks.last == pen && interaction.selectedIndex == 2)
        interaction.key(.undo)
        interaction.key(.undo)
        #expect(interaction.marks.marks.count == 3 && interaction.marks.marks[1] == pen)
    }

    @Test func copyCutAndPasteDoNothingWithNoBoxDuringADragOrWhileATextIsOpen() async throws {
        let clipboard = MarkClipboard()
        clipboard.copy(Mark(tool: .number, style: .initial(for: .number), points: [CGPoint(x: 30, y: 30)], number: 3))
        let harness = try await Harness(clipboard: clipboard)
        let interaction = harness.interaction
        // No box exists yet (row 17).
        interaction.key(.paste)
        #expect(interaction.marks.isEmpty && interaction.selection(on: retina) == nil)

        // The first mark of the capture is a paste: the box is fixed and has no handles (row 22).
        // The copy of number 3 is 3, and the Number tool then gives 4 (row 25).
        harness.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 140, y: 80), on: retina)
        #expect(interaction.showsHandles)
        interaction.key(.paste)
        #expect(interaction.marks.marks.map(\.number) == [3] && !interaction.showsHandles)
        interaction.selectTool(.number)
        harness.click(at: CGPoint(x: 120, y: 40), on: retina)
        #expect(interaction.marks.marks.map(\.number) == [3, 4])

        // During a drag of number 4, the keys do nothing (rows 5 and 19). The clipboard still has number 3.
        interaction.toggleSelecting()
        interaction.pointerDown(at: CGPoint(x: 120, y: 40), on: retina)
        interaction.pointerDragged(to: CGPoint(x: 115, y: 45))
        interaction.key(.copy)
        interaction.key(.cut)
        interaction.key(.paste)
        interaction.pointerUp(at: CGPoint(x: 115, y: 45))
        #expect(interaction.marks.marks.map(\.number) == [3, 4])
        interaction.key(.paste)
        #expect(interaction.marks.marks.map(\.number) == [3, 4, 3])

        // While a text is open, a paste adds no mark (row 18). The view gives the keys to the field.
        interaction.selectTool(.text)
        harness.click(at: CGPoint(x: 60, y: 70), on: retina)
        interaction.key(.paste)
        #expect(interaction.textEdit != nil && interaction.marks.marks.count == 3)
    }

    @Test func aMarkThatWasCopiedInOneCapturePastesIntoTheNext() async throws {
        let clipboard = MarkClipboard()
        let first = try await harnessWithMarks(clipboard: clipboard)
        first.click(at: CGPoint(x: 80, y: 45), on: retina)
        first.interaction.key(.copy)
        first.interaction.key(.enter)
        #expect(first.doneResult != nil)

        // Done does not clear the clipboard (row 24). The next box is 40 by 30 points: smaller than the
        // rectangle with its line, so the copy keeps its top-left corner in the box (row 23).
        let second = try await Harness(clipboard: clipboard)
        second.drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 40), on: retina)
        second.interaction.key(.paste)
        let pasted = try #require(second.interaction.marks.marks.first)
        #expect(pasted.tool == .rectangle && pasted.bounds.origin == .zero)
    }
}
