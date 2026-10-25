import AppKit
import Carbon.HIToolbox
@testable import ScreenshotKit
import Testing

extension Toolbar {
    /// The button with the given name ("Rectangle", "Undo", "Thick", "Blue" and so on). The sizes
    /// and the colours are in a row view, one level below the buttons of the main row.
    func button(named name: String) -> NSButton? {
        (subviews + subviews.flatMap(\.subviews)).compactMap { $0 as? ToolbarButton }.first { $0.name == name }
    }
}

/// The view adapter, out of sight. The test hands `NSEvent` objects to the view (it posts no
/// event to macOS) and draws the layers of the view into a bitmap. No window is shown.
@MainActor @Suite struct OverlayViewTests {
    /// One overlay view on a fake screen, wired as `CaptureSession` wires it.
    @MainActor final class Stage {
        let display: FrozenDisplay
        let interaction: CaptureInteraction
        let view: OverlayView
        var outcomes: [CaptureOutcome] = []

        init(
            display: FrozenDisplay, windows: [CGRect] = [], startTool: Tool? = nil,
            view: ((CaptureInteraction) -> OverlayView)? = nil
        ) {
            self.display = display
            interaction = CaptureInteraction(
                displays: [display],
                windows: [display.displayID: windows],
                toolbarKeys: ToolbarKeys(defaults: MemoryDefaults()),
                startTool: startTool,
                styles: ToolStyleMemory(),
                clipboard: MarkClipboard()
            )
            self.view = view?(interaction) ?? OverlayView(display: display, interaction: interaction)
            interaction.onChange = { [unowned self] in self.view.refresh() }
            interaction.onFinish = { [unowned self] in self.outcomes.append($0) }
        }

        /// 200 by 100 points at scale 2.
        static func retina() async throws -> Stage {
            Stage(display: try await FakeScreenCapture().freezeAllDisplays()[0])
        }

        /// 800 by 600 points at scale 1: room for the toolbar.
        static var largeDisplay: FrozenDisplay {
            FrozenDisplay(
                displayID: 9,
                image: makePatternImage(width: 800, height: 600),
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                scale: 1
            )
        }

        /// 400 by 300 points at scale 2.
        static var largeRetinaDisplay: FrozenDisplay {
            FrozenDisplay(
                displayID: 8,
                image: makePatternImage(width: 800, height: 600),
                frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                scale: 2
            )
        }

        /// A mouse event at a point with a top-left origin. AppKit itself counts from the bottom.
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ yFromTop: CGFloat, clicks: Int = 1) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: x, y: view.bounds.height - yFromTop),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: clicks,
                pressure: 1
            ))
        }

        func key(
            _ keyCode: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = [], isARepeat: Bool = false
        ) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: isARepeat,
                keyCode: keyCode
            ))
        }

        func drag(from start: CGPoint, to end: CGPoint) throws {
            view.mouseDown(with: try mouse(.leftMouseDown, start.x, start.y))
            view.mouseDragged(with: try mouse(.leftMouseDragged, end.x, end.y))
            view.mouseUp(with: try mouse(.leftMouseUp, end.x, end.y))
        }

        func click(at point: CGPoint) throws {
            view.mouseDown(with: try mouse(.leftMouseDown, point.x, point.y))
            view.mouseUp(with: try mouse(.leftMouseUp, point.x, point.y))
        }

        /// A click on a button of the toolbar: its action, as AppKit sends it.
        func press(_ name: String) throws {
            let button = try #require(view.toolbar.button(named: name))
            #expect(button.isEnabled, "the button \(name) is not enabled")
            // The action goes through the app object. It is an accessory app: no Dock icon, no window.
            NSApplication.shared.setActivationPolicy(.accessory)
            #expect(button.sendAction(button.action, to: button.target))
        }

        var boxRect: CGRect? { interaction.selection(on: display.displayID)?.rect }

        /// What the overlay shows, in the pixels of the display (top-left origin).
        func renderedPixels() throws -> PixelReader {
            let scale = display.scale
            let width = Int(view.bounds.width * scale)
            let height = Int(view.bounds.height * scale)
            let context = try #require(CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.scaleBy(x: scale, y: scale)
            // The layers of the canvas. A view that is in no window does not put them in its own layer.
            view.canvasLayer.render(in: context)
            return PixelReader(try #require(context.makeImage()))
        }
    }

    @Test func aMouseDragMakesTheBoxAndTheOverlayShowsItWithItsHandles() async throws {
        let stage = try await Stage.retina()
        let view = stage.view
        // Before a drag, the full screen is dim. The dim is 55% black, so a pixel keeps 45% of the
        // frozen image (YAZ-2910). The center of the screen is the same: no text is there.
        let before = try stage.renderedPixels()
        for (x, y) in [(60, 40), (200, 100)] {
            let frozen = patternPixel(x: x, y: y)
            #expect(abs(Int(before[x, y].red) - Int(frozen.red) * 45 / 100) <= 1)
            #expect(abs(Int(before[x, y].green) - Int(frozen.green) * 45 / 100) <= 1)
        }
        #expect(view.toolbar.isHidden)

        view.mouseDown(with: try stage.mouse(.leftMouseDown, 20, 10))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 150, 70))
        #expect(stage.boxRect == CGRect(x: 20, y: 10, width: 130, height: 60))

        // The box is x 40 to 300 and y 20 to 140 in pixels. During the drag, the overlay shows the
        // frozen image exactly in the box: upright, not dim, also the first and the last pixel.
        let during = try stage.renderedPixels()
        #expect(during[40, 20] == patternPixel(x: 40, y: 20))
        #expect(during[299, 139] == patternPixel(x: 299, y: 139))
        #expect(during[200, 100] == patternPixel(x: 200, y: 100))
        // The box is at the top of the screen, so its size label is inside it, at the top-left.
        #expect(during[60, 40] != patternPixel(x: 60, y: 40))
        #expect(view.toolbar.isHidden)

        view.mouseUp(with: try stage.mouse(.leftMouseUp, 150, 70))
        let after = try stage.renderedPixels()
        // The first and the last row and column of the box are still the frozen image.
        #expect(after[60, 20] == patternPixel(x: 60, y: 20))
        #expect(after[60, 139] == patternPixel(x: 60, y: 139))
        #expect(after[40, 60] == patternPixel(x: 40, y: 60))
        #expect(after[299, 60] == patternPixel(x: 299, y: 60))
        // The border is the 1 point outside the box, and it is blue.
        #expect(after[39, 60].blue > 200 && after[39, 60].red < 80)
        #expect(after[300, 60].blue > 200 && after[300, 60].red < 80)
        // Away from the box, the screen is still dim.
        #expect(after[350, 180].red < patternPixel(x: 350, y: 180).red)
        #expect(after[350, 180].green < patternPixel(x: 350, y: 180).green)

        // After the release the box has eight white handles with a blue edge, 7 points wide.
        let selection = try #require(stage.interaction.selection(on: stage.display.displayID))
        for handle in Handle.allCases {
            let middle = selection.handlePoint(handle)
            #expect(after[Int(middle.x) * 2, Int(middle.y) * 2] == .white, "handle \(handle)")
        }
        // The top-left handle is x 16 to 23, y 6 to 13 in points: pixels 32 to 45, and 12 to 25.
        let whiteRow = (20..<60).filter { after[$0, 19] == .white }
        #expect(whiteRow == Array(34...43)) // 7 points, without the 1 point edge at each side
        #expect(after[32, 19].blue > 200 && after[32, 19].red < 80)
        #expect(after[45, 19].blue > 200 && after[45, 19].red < 80)
        #expect(after[31, 19] != .white && after[46, 19] != .white)
        #expect(!view.toolbar.isHidden)
    }

    @Test func enterEscAndTheMouseButtonsReachTheInteraction() async throws {
        let stage = try await Stage.retina()
        let view = stage.view

        view.keyDown(with: try stage.key(36)) // Return with no box: nothing
        view.keyDown(with: try stage.key(0, "a")) // the key A: nothing
        #expect(stage.outcomes.isEmpty)

        try stage.drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70))

        // A right-click removes the box.
        view.rightMouseDown(with: try stage.mouse(.rightMouseDown, 5, 5))
        #expect(stage.boxRect == nil)
        #expect(stage.outcomes.isEmpty)

        // A new box, then a double-click in it: done.
        try stage.drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70))
        try stage.click(at: CGPoint(x: 30, y: 20))
        #expect(stage.outcomes.isEmpty)
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 30, 20, clicks: 2))
        guard case .done(let result)? = stage.outcomes.first, stage.outcomes.count == 1 else {
            Issue.record("A double-click in the box must report one done")
            return
        }
        #expect(result.selection.rect == CGRect(x: 20, y: 10, width: 130, height: 60))
    }

    @Test func escCancels() async throws {
        let stage = try await Stage.retina()
        stage.view.keyDown(with: try stage.key(53))
        guard case .cancel? = stage.outcomes.first, stage.outcomes.count == 1 else {
            Issue.record("Esc must report one cancel")
            return
        }
    }

    // MARK: The marks (YAZ-2767)

    @Test func theOverlayShowsTheMarksWithTheSamePixelsAsTheSavedImage() async throws {
        // 400 by 300 points at scale 2. The box is x 50 to 250, y 60 to 160: pixels 100 to 500, and
        // 120 to 320. Its label is above it and its toolbar is below it, so nothing covers the box.
        let stage = Stage(display: Stage.largeRetinaDisplay)
        let view = stage.view
        try stage.drag(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 250, y: 160))

        // A highlight, and a blue rectangle above it. The second mark is still in its drag.
        try stage.press("Highlight")
        try stage.drag(from: CGPoint(x: 70, y: 110), to: CGPoint(x: 230, y: 112))
        try stage.press("Rectangle")
        try stage.press("Blue")
        try stage.press("Thick")
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 90, 80))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 200, 140))
        #expect(stage.interaction.marks.marks.count == 1)
        // The mark shows already during the drag: its left edge is at 90 points, 180 pixels.
        #expect(try stage.renderedPixels()[180, 200].isNear(Pixel(.blue)))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 200, 140))
        #expect(stage.interaction.marks.marks.map(\.tool) == [.highlight, .rectangle])
        #expect(stage.boxRect == CGRect(x: 50, y: 60, width: 200, height: 100))

        // Each pixel of the box in the overlay is the pixel of the image that the file gets.
        // That also proves that the box has no handles now.
        let selection = try #require(stage.interaction.selection(on: stage.display.displayID))
        let final = PixelReader(try composeFinalImage(frozen: stage.display, selection: selection, marks: stage.interaction.marks))
        #expect(final.width == 400 && final.height == 200)
        func differences(_ overlay: PixelReader, from image: PixelReader) -> Int {
            var count = 0
            for y in 0..<image.height {
                for x in 0..<image.width where overlay[100 + x, 120 + y] != image[x, y] {
                    count += 1
                }
            }
            return count
        }
        #expect(differences(try stage.renderedPixels(), from: final) == 0)
        // The image has the marks: blue on the rectangle, and the highlight changed the pixels below it.
        #expect(final[80, 80].isNear(Pixel(.blue)))
        let plain = PixelReader(try composeFinalImage(frozen: stage.display, selection: selection, marks: MarkList()))
        #expect(differences(try stage.renderedPixels(), from: plain) > 5_000)

        // Command-Z removes the last mark, and Shift-Command-Z puts it back.
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: .command)))
        #expect(stage.interaction.marks.marks.map(\.tool) == [.highlight])
        #expect(!(try stage.renderedPixels()[180, 200].isNear(Pixel(.blue))))
        #expect(view.performKeyEquivalent(with: try stage.key(6, "Z", flags: [.command, .shift])))
        #expect(stage.interaction.marks.marks.map(\.tool) == [.highlight, .rectangle])
        #expect(differences(try stage.renderedPixels(), from: final) == 0)
        // A different key with Command is not for the overlay.
        #expect(!view.performKeyEquivalent(with: try stage.key(12, "q", flags: .command)))

        // Undo of all marks: the box shows the frozen image again, and its handles are back.
        try stage.press("Undo")
        try stage.press("Undo")
        #expect(view.toolbar.button(named: "Undo")?.isEnabled == false)
        let empty = try stage.renderedPixels()
        #expect(empty[180, 200] == patternPixel(x: 180, y: 200))
        #expect(empty[100, 120] == .white) // the top-left handle
    }

    // MARK: The toolbar (YAZ-2767)

    @Test func eachTipTellsTheNameAndTheKeys() async throws {
        func tip(_ name: String, hotKey: HotKeyCombo?) -> String? {
            let interaction = CaptureInteraction(
                displays: [Stage.largeDisplay], hotKey: hotKey, toolbarKeys: ToolbarKeys(defaults: MemoryDefaults()),
                styles: ToolStyleMemory()
            )
            return (Toolbar(interaction: interaction).button(named: name) as? ToolbarButton)?.tip
        }
        #expect(tip("Done", hotKey: .shiftCommandD) == "Done  ↩ or ⇧⌘D")
        // The hotkey from the settings, also when it is not the default.
        #expect(tip("Done", hotKey: HotKeyCombo(keyCode: UInt32(kVK_F5), modifiers: [.control, .option])) == "Done  ↩ or ⌃⌥F5")
        // macOS refused the hotkey: the tip does not show a key that does not work.
        #expect(tip("Done", hotKey: nil) == "Done  ↩")
        // The other tips tell the key too (D3, YAZ-2872).
        #expect(tip("Undo", hotKey: .shiftCommandD) == "Undo  ⌘Z")
        #expect(tip("Cancel", hotKey: .shiftCommandD) == "Cancel  Esc")
        #expect(tip("Rectangle", hotKey: .shiftCommandD) == "Rectangle  R")
        #expect(tip("Select", hotKey: .shiftCommandD) == "Select  V")
        #expect(tip("Medium", hotKey: .shiftCommandD) == "Medium  2")
        #expect(tip("Blue", hotKey: .shiftCommandD) == "Blue  7")

        // Done is at the right end of the toolbar. Its tip does not go past the right end.
        let toolbar = Toolbar(interaction: CaptureInteraction(
            displays: [Stage.largeDisplay], hotKey: .shiftCommandD, styles: ToolStyleMemory()
        ))
        let done = try #require(toolbar.button(named: "Done") as? ToolbarButton)
        done.onHover?(done, true)
        let shown = try #require(toolbar.subviews.compactMap { $0 as? NSTextField }.first { !$0.isHidden })
        #expect(shown.stringValue == "Done  ↩ or ⇧⌘D")
        #expect(shown.frame.maxX <= toolbar.bounds.maxX && shown.frame.minX >= toolbar.bounds.minX)
    }

    @Test func theToolbarIsBelowTheBoxFollowsItAndSelectsTheTools() async throws {
        let stage = Stage(display: Stage.largeDisplay)
        let view = stage.view
        let toolbar = view.toolbar

        // The toolbar shows when the box exists and the pointer is released.
        #expect(toolbar.isHidden)
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 100, 100))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 500, 300))
        #expect(toolbar.isHidden)
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 500, 300))
        #expect(!toolbar.isHidden)

        /// The frame of the toolbar with a top-left origin, as the scenario rows tell it.
        func frame() -> CGRect {
            CGRect(x: toolbar.frame.minX, y: 600 - toolbar.frame.maxY, width: toolbar.frame.width, height: toolbar.frame.height)
        }
        // Below the box (8 points), with its right edge on the right edge of the box.
        #expect(frame() == CGRect(x: 150, y: 308, width: 350, height: 36))

        /// The pixels of light text in an area of the dim screen: the text of the size label.
        func lightPixels(x: Range<Int>, y: Range<Int>) throws -> Int {
            let pixels = try stage.renderedPixels()
            var count = 0
            for row in y {
                for column in x where pixels[column, row].red > 160 && pixels[column, row].green > 160 && pixels[column, row].blue > 160 {
                    count += 1
                }
            }
            return count
        }
        // The size label is above the top-left corner of the box, which is at 100, 100.
        #expect(try lightPixels(x: 100..<200, y: 78..<95) > 10)
        #expect(try lightPixels(x: 250..<400, y: 60..<95) == 0)

        // The toolbar and the label move with the box, also during the drag.
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 300, 200))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 350, 220))
        #expect(frame() == CGRect(x: 200, y: 328, width: 350, height: 36))
        #expect(try lightPixels(x: 100..<200, y: 78..<95) == 0)
        #expect(try lightPixels(x: 150..<250, y: 98..<115) > 10)
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 350, 220))
        // It follows a size change.
        try stage.drag(from: CGPoint(x: 550, y: 320), to: CGPoint(x: 600, y: 400))
        #expect(stage.boxRect == CGRect(x: 150, y: 120, width: 450, height: 280))
        #expect(frame() == CGRect(x: 250, y: 408, width: 350, height: 36))

        // The buttons, in the order of the toolbar, each with its name.
        // "Select" is the first button (YAZ-2782 row 1).
        let names = ["Select", "Rectangle", "Ellipse", "Arrow", "Pen", "Highlight", "Text", "Number", "Undo", "Cancel", "Done"]
        let buttons = try names.map { try #require(toolbar.button(named: $0)) }
        #expect(buttons.map(\.frame.minX) == buttons.map(\.frame.minX).sorted())
        // Each button has its symbol. A symbol name that macOS does not have gives an empty picture.
        #expect(buttons.allSatisfy { ($0.image?.size.width ?? 0) > 0 && $0.superview === toolbar })
        #expect(toolbar.button(named: "Undo")?.isEnabled == false)

        // The row with the sizes and the colours shows only when a tool is selected.
        let red = try #require(toolbar.button(named: "Red") as? ToolbarButton)
        let optionsRow = try #require(red.superview)
        #expect(optionsRow.isHidden)
        try stage.press("Rectangle")
        #expect(stage.interaction.tool == .rectangle)
        #expect(!optionsRow.isHidden)
        #expect(frame() == CGRect(x: 250, y: 408, width: 350, height: 72))
        #expect((toolbar.button(named: "Rectangle") as? ToolbarButton)?.isOn == true)
        // The first time: red and Thick (D15 on YAZ-2782).
        let thick = try #require(toolbar.button(named: "Thick") as? ToolbarButton)
        #expect(red.isOn && thick.isOn)

        try stage.press("Blue")
        try stage.press("Medium")
        #expect(stage.interaction.style == MarkStyle(color: .blue, size: .medium))
        #expect(!red.isOn && !thick.isOn)
        #expect((toolbar.button(named: "Blue") as? ToolbarButton)?.isOn == true)
        // Highlight has its own colour: amber.
        try stage.press("Highlight")
        #expect((toolbar.button(named: "Amber") as? ToolbarButton)?.isOn == true)
        #expect((toolbar.button(named: "Rectangle") as? ToolbarButton)?.isOn == false)

        // The pointer above a button shows the name of the button, below the toolbar.
        let tip = try #require(toolbar.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(tip.isHidden)
        let pen = try #require(toolbar.button(named: "Pen"))
        func hover(_ type: NSEvent.EventType) throws -> NSEvent {
            try #require(NSEvent.enterExitEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
            ))
        }
        pen.mouseEntered(with: try hover(.mouseEntered))
        #expect(!tip.isHidden && tip.stringValue == "Pen  W")
        #expect(tip.frame.minY >= toolbar.bounds.maxY && abs(tip.frame.midX - pen.frame.midX) <= 1)
        pen.mouseExited(with: try hover(.mouseExited))
        #expect(tip.isHidden)

        // A click on the selected tool clears the selection, and the second row goes away.
        try stage.press("Highlight")
        #expect(stage.interaction.tool == nil && optionsRow.isHidden)
        #expect(frame() == CGRect(x: 250, y: 408, width: 350, height: 36))

        // A mark makes Undo active.
        try stage.press("Arrow")
        try stage.drag(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 300, y: 250))
        #expect(toolbar.button(named: "Undo")?.isEnabled == true)

        // A click on the toolbar between two buttons is not a click on the overlay.
        #expect(view.hitTest(CGPoint(x: toolbar.frame.minX + 1, y: toolbar.frame.maxY - 1)) === toolbar)
        #expect(view.hitTest(CGPoint(x: toolbar.frame.minX + 1, y: toolbar.frame.minY + 1))?.isDescendant(of: toolbar) == true)
        #expect(view.hitTest(CGPoint(x: 20, y: 20)) === view)

        // Done is the same as Enter.
        try stage.press("Done")
        guard case .done(let result)? = stage.outcomes.first, stage.outcomes.count == 1 else {
            Issue.record("Done must report one done")
            return
        }
        #expect(result.marks.marks.map(\.tool) == [.arrow])
    }

    @Test func theToolbarGoesAboveOrInsideTheBoxAndCancelCancels() async throws {
        let stage = Stage(display: Stage.largeDisplay)
        let toolbar = stage.view.toolbar
        func top() -> CGFloat { 600 - toolbar.frame.maxY }

        // No room below: above the box. The label would be below the toolbar, so it goes inside the box.
        try stage.drag(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 500, y: 580))
        #expect(top() == 256) // 300 - 8 - 36
        // The box has the full height of the screen: inside the box, at the bottom-right.
        stage.view.rightMouseDown(with: try stage.mouse(.rightMouseDown, 5, 5))
        #expect(toolbar.isHidden)
        try stage.drag(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 500, y: 600))
        #expect(top() == 600 - 8 - 36 && toolbar.frame.maxX == 500 - 8)
        // A narrow box at the left: the toolbar stays on the screen.
        stage.view.rightMouseDown(with: try stage.mouse(.rightMouseDown, 5, 5))
        try stage.drag(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 60, y: 200))
        #expect(toolbar.frame.minX == 0 && top() == 208)

        try stage.press("Cancel")
        guard case .cancel? = stage.outcomes.first, stage.outcomes.count == 1 else {
            Issue.record("Cancel must report one cancel")
            return
        }
    }

    // MARK: The toolbar keys (YAZ-2872)

    /// The flow of the request: drag a box, press R, drag. The result is a rectangle.
    @Test func dragABoxPressRAndDragGivesARectangle() async throws {
        let stage = Stage(display: Stage.largeDisplay)
        let view = stage.view
        try stage.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 300))

        view.keyDown(with: try stage.key(UInt16(kVK_ANSI_R), "r"))
        #expect(stage.interaction.tool == .rectangle)
        // The colour key 7 changes the next rectangle to blue.
        view.keyDown(with: try stage.key(UInt16(kVK_ANSI_7), "7"))
        try stage.drag(from: CGPoint(x: 150, y: 150), to: CGPoint(x: 250, y: 220))
        #expect(stage.interaction.marks.marks.map(\.tool) == [.rectangle])
        #expect(stage.interaction.marks.marks.first?.style.color == .blue)

        // A second R keeps the tool, so the next drag draws and does not move the box (D2).
        view.keyDown(with: try stage.key(UInt16(kVK_ANSI_R), "r"))
        try stage.drag(from: CGPoint(x: 300, y: 150), to: CGPoint(x: 400, y: 250))
        #expect(stage.interaction.marks.marks.count == 2)
        #expect(stage.boxRect == CGRect(x: 100, y: 100, width: 400, height: 200))

        // A key that stays down changes nothing. Command-O is not a toolbar key. Shift-O is O.
        view.keyDown(with: try stage.key(UInt16(kVK_ANSI_O), "o", isARepeat: true))
        #expect(stage.interaction.tool == .rectangle)
        #expect(!view.performKeyEquivalent(with: try stage.key(UInt16(kVK_ANSI_O), "o", flags: .command)))
        view.keyDown(with: try stage.key(UInt16(kVK_ANSI_O), "o", flags: .command))
        #expect(stage.interaction.tool == .rectangle)
        view.keyDown(with: try stage.key(UInt16(kVK_ANSI_O), "O", flags: .shift))
        #expect(stage.interaction.tool == .ellipse)
        #expect(stage.outcomes.isEmpty)
    }

    /// The letters show only while the pointer is on the toolbar (D3).
    @Test func theLettersShowOnlyWhileThePointerIsOnTheToolbar() async throws {
        let stage = Stage(display: Stage.largeDisplay)
        try stage.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 300))
        stage.view.keyDown(with: try stage.key(UInt16(kVK_ANSI_R), "r"))
        let toolbar = stage.view.toolbar
        let rectangle = try #require(toolbar.button(named: "Rectangle") as? ToolbarButton)
        let blue = try #require(toolbar.button(named: "Blue") as? ToolbarButton)
        let undo = try #require(toolbar.button(named: "Undo") as? ToolbarButton)

        func pointer(_ type: NSEvent.EventType) throws -> NSEvent {
            try #require(NSEvent.enterExitEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
            ))
        }
        #expect(rectangle.keyText == nil && blue.keyText == nil)
        toolbar.mouseEntered(with: try pointer(.mouseEntered))
        #expect(rectangle.keyText?.string == "R")
        #expect(blue.keyText?.string == "7")
        // Undo has a fixed key. It shows no letter. Its tip names the key.
        #expect(undo.keyText == nil)
        toolbar.mouseExited(with: try pointer(.mouseExited))
        #expect(rectangle.keyText == nil && blue.keyText == nil)

        // The toolbar hides with the pointer on it (a new box, for example): the letters go too.
        toolbar.mouseEntered(with: try pointer(.mouseEntered))
        toolbar.isHidden = true
        #expect(rectangle.keyText == nil)
    }

    // MARK: The start tool (YAZ-2879)

    /// The flow of the request: drag a box, then drag in it. The result is a rectangle, with no key
    /// and no click on the toolbar.
    @Test func dragABoxThenDragInItGivesARectangle() async throws {
        let stage = Stage(display: Stage.largeDisplay, startTool: .rectangle)
        try stage.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 300))
        let rectangle = try #require(stage.view.toolbar.button(named: "Rectangle") as? ToolbarButton)
        #expect(rectangle.isOn && !stage.view.toolbar.isHidden)

        try stage.drag(from: CGPoint(x: 150, y: 150), to: CGPoint(x: 250, y: 220))
        #expect(stage.interaction.marks.marks.map(\.tool) == [.rectangle])
        #expect(stage.boxRect == CGRect(x: 100, y: 100, width: 400, height: 200))

        // A double-click in the box finishes, also with the Rectangle on.
        stage.view.mouseDown(with: try stage.mouse(.leftMouseDown, 300, 200, clicks: 2))
        guard case .done(let result)? = stage.outcomes.first else {
            Issue.record("A double-click with the Rectangle must finish")
            return
        }
        #expect(result.marks.marks.count == 1)
    }

    // MARK: The text field and the panel (YAZ-2767 and the keyboard decision on YAZ-2765)

    @Test func thePanelTakesTheKeyboardAndTheTextFieldTakesTheTyping() async throws {
        // The window is made but never shown: no call puts it on a screen.
        NSApplication.shared.setActivationPolicy(.accessory)
        var window: OverlayWindow?
        let stage = Stage(display: Stage.largeDisplay) { interaction in
            let made = OverlayWindow(display: Stage.largeDisplay, interaction: interaction)
            window = made
            return made.overlayView
        }
        let panel = try #require(window)
        let view = stage.view
        defer { panel.close() }

        // A panel that takes the keyboard with no app switch, and stays when the app is not active.
        #expect(panel.styleMask.contains(.nonactivatingPanel) && !panel.styleMask.contains(.titled))
        #expect(panel.canBecomeKey && !panel.becomesKeyOnlyIfNeeded && !panel.hidesOnDeactivate)
        #expect(panel.level == .screenSaver && !panel.isFloatingPanel)
        #expect(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]))
        #expect(panel.contentView === view && panel.firstResponder === view)

        try stage.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 300))
        try stage.press("Text")
        // Medium is 18 points. The first size is Thick, 24 points.
        #expect(stage.interaction.style?.fontSize == 24)
        try stage.press("Medium")
        #expect(view.textView == nil)

        // A click in the box puts a text field at that point. The field has the keyboard.
        try stage.click(at: CGPoint(x: 200, y: 150))
        var field = try #require(view.textView)
        #expect(panel.firstResponder === field)
        #expect(field.superview === view)
        // The text starts 39 points below the top of the box: the click at 50 is the middle of a
        // line of 23 points. The field goes to the right and the bottom edge of the box.
        #expect(field.frame == CGRect(x: 200, y: 300, width: 300, height: 161))
        #expect(field.font?.pointSize == 18)
        #expect(field.textContainer?.size.width == 300 && field.textContainer?.lineFragmentPadding == 0)

        // Typing goes to the interaction. Return completes the text, and the keyboard goes back to the overlay.
        field.insertText("Hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(stage.interaction.textEdit?.text == "Hello")
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(view.textView == nil && field.superview == nil)
        #expect(panel.firstResponder === view)
        let hello = try #require(stage.interaction.marks.marks.last)
        #expect(hello.text == "Hello" && hello.points == [CGPoint(x: 100, y: 39)] && hello.wrapWidth == 300)
        // Return also selected the text (YAZ-3318 D6). Esc clears the selection, so the overlay
        // shows no outline below.
        #expect(stage.interaction.selectedIndex == 0)
        stage.interaction.key(.escape)
        #expect(stage.interaction.selectedIndex == nil && stage.interaction.textEdit == nil)

        // The saved image has the text where the field showed it, and the overlay shows the same pixels.
        let selection = try #require(stage.interaction.selection(on: stage.display.displayID))
        let final = PixelReader(try composeFinalImage(frozen: stage.display, selection: selection, marks: stage.interaction.marks))
        let plain = PixelReader(try composeFinalImage(frozen: stage.display, selection: selection, marks: MarkList()))
        let overlay = try stage.renderedPixels()
        var textPixels = 0
        for y in 0..<final.height {
            for x in 0..<final.width {
                if overlay[100 + x, 100 + y] != final[x, y] {
                    Issue.record("The overlay differs from the saved image at \(x), \(y)")
                    return
                }
                if final[x, y] != plain[x, y] {
                    textPixels += 1
                    // "Hello" at 18 points: all its pixels are in the first line of the field.
                    if !((100..<160).contains(x) && (39..<62).contains(y)) {
                        Issue.record("A pixel of the text is outside the first line of the field: \(x), \(y)")
                        return
                    }
                }
            }
        }
        #expect(textPixels > 100)

        // A change of the colour while a text is open applies to the field. Return turned the
        // Text tool off, so the test selects it again.
        try stage.press("Text")
        try stage.click(at: CGPoint(x: 300, y: 250))
        field = try #require(view.textView)
        field.insertText("Two words", replacementRange: NSRange(location: NSNotFound, length: 0))
        try stage.press("Blue")
        #expect(view.textView === field)
        #expect(field.textColor == NSColor(cgColor: MarkRenderer.color(.blue)))
        #expect(stage.interaction.textEdit?.text == "Two words")

        // A click on the text is for the field (it moves the caret). A click away from it is for the overlay.
        let onText = CGPoint(x: field.frame.minX + 10, y: field.frame.maxY - 8)
        #expect(view.hitTest(onText) === field)
        #expect(view.hitTest(CGPoint(x: field.frame.minX + 150, y: field.frame.maxY - 8)) === view)
        #expect(view.hitTest(CGPoint(x: 150, y: 450)) === view)

        // A click in a different place completes the text, and puts a new field there.
        try stage.click(at: CGPoint(x: 150, y: 120))
        #expect(stage.interaction.marks.marks.map(\.text) == ["Hello", "Two words"])
        #expect(stage.interaction.marks.marks.last?.style.color == .blue)
        let next = try #require(view.textView)
        #expect(next !== field && panel.firstResponder === next)

        // Esc removes the text that is not complete. The capture stays open.
        next.insertText("gone", replacementRange: NSRange(location: NSNotFound, length: 0))
        next.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(view.textView == nil && stage.interaction.marks.marks.count == 2 && stage.outcomes.isEmpty)
        #expect(panel.firstResponder === view)

        // Done while a text is open: the text is completed first.
        try stage.click(at: CGPoint(x: 150, y: 120))
        try #require(view.textView).insertText("Last", replacementRange: NSRange(location: NSNotFound, length: 0))
        try stage.press("Done")
        guard case .done(let result)? = stage.outcomes.first, stage.outcomes.count == 1 else {
            Issue.record("Done must report one done")
            return
        }
        #expect(result.marks.marks.map(\.text) == ["Hello", "Two words", "Last"])
        #expect(!panel.isVisible)
    }

    // MARK: Select a mark (YAZ-2782)

    @Test func theOverlayShowsTheSelectedMarkWithAnOutlineAndHandlesAndTheSavedImageHasNone() async throws {
        // 400 by 300 points at scale 2, in a panel that is never shown. The box is x 50 to 250,
        // y 60 to 160: pixels 100 to 500, and 120 to 320. Its label is above it.
        NSApplication.shared.setActivationPolicy(.accessory)
        var window: OverlayWindow?
        let stage = Stage(display: Stage.largeRetinaDisplay) { interaction in
            let made = OverlayWindow(display: Stage.largeRetinaDisplay, interaction: interaction)
            window = made
            return made.overlayView
        }
        let panel = try #require(window)
        defer { panel.close() }
        let view = stage.view, toolbar = view.toolbar, interaction = stage.interaction
        try stage.drag(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 250, y: 160))
        let selection = try #require(interaction.selection(on: stage.display.displayID))

        // "Select" is the first button, with the arrow pointer symbol, and its name shows on hover (row 1).
        let select = try #require(toolbar.button(named: "Select") as? ToolbarButton)
        let rectangleButton = try #require(toolbar.button(named: "Rectangle") as? ToolbarButton)
        #expect(select.frame.minX == 4 && rectangleButton.frame.minX == 34)
        #expect(select.image?.accessibilityDescription == "Select")
        let tip = try #require(toolbar.subviews.compactMap { $0 as? NSTextField }.first)
        select.mouseEntered(with: try #require(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        )))
        #expect(!tip.isHidden && tip.stringValue == "Select  V")

        // Two marks: a Thick red rectangle, x 90 to 200 and y 80 to 140 of the screen, and the
        // text "Hello" inside it, at 110, 90.
        try stage.press("Rectangle")
        try stage.drag(from: CGPoint(x: 90, y: 80), to: CGPoint(x: 200, y: 140))
        try stage.press("Text")
        try stage.click(at: CGPoint(x: 110, y: 105))
        var field = try #require(view.textView)
        field.insertText("Hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle, .text])
        #expect(interaction.marks.marks[1].points == [CGPoint(x: 60, y: 30)])

        // Return selects the new text, with "Select" on (YAZ-3318 D6). The text shows four white
        // handles, at the corners of its outline (D3). Its font is 24, so Thick is on (D7).
        #expect(interaction.isSelecting && interaction.selectedIndex == 1 && interaction.tool == nil)
        let hello = try #require(interaction.selectedMark)
        #expect(hello.handles.count == 4)
        let withHandles = try stage.renderedPixels()
        for corner in hello.handles.map(\.point) {
            let x = Int(((50 + corner.x) * 2).rounded()), y = Int(((60 + corner.y) * 2).rounded())
            #expect(withHandles[x, y] == .white, "the handle at \(corner)")
        }
        let thick = try #require(toolbar.button(named: "Thick") as? ToolbarButton)
        #expect(thick.isOn)
        // A digit gives 32 points (D2). No size has 32 points, so no size is on (D7).
        interaction.toolbarKey("5")
        #expect(interaction.marks.marks[1].style.fontSize == 32 && !thick.isOn)
        interaction.undo()

        // "Select" with no selected mark: the second row does not show (row 3), and the box in the
        // overlay is the image that the file gets.
        #expect(interaction.marks.marks[1] == hello && interaction.selectedIndex == nil)
        let optionsRow = try #require(toolbar.button(named: "Red")?.superview)
        #expect(interaction.isSelecting && select.isOn && !rectangleButton.isOn && optionsRow.isHidden)
        func savedImage() throws -> PixelReader {
            PixelReader(try composeFinalImage(frozen: stage.display, selection: selection, marks: interaction.marks))
        }
        /// The pixels of the box in the overlay that are not the pixels of the image.
        func differences(from image: PixelReader) throws -> Int {
            let overlay = try stage.renderedPixels()
            var count = 0
            for y in 0..<image.height {
                for x in 0..<image.width where overlay[100 + x, 120 + y] != image[x, y] {
                    count += 1
                }
            }
            return count
        }
        let final = try savedImage()
        #expect(final.width == 400 && final.height == 200)
        #expect(try differences(from: final) == 0)

        // A click on the line of the rectangle selects it. The second row shows its colour and its size.
        try stage.click(at: CGPoint(x: 90, y: 110))
        #expect(interaction.selectedIndex == 0 && !optionsRow.isHidden)
        #expect((toolbar.button(named: "Red") as? ToolbarButton)?.isOn == true)
        #expect((toolbar.button(named: "Thick") as? ToolbarButton)?.isOn == true)

        // The overlay shows eight white handles, on the corners and the edge middles of the rectangle (row 10).
        let selected = try stage.renderedPixels()
        for (x, y) in [(90, 80), (145, 80), (200, 80), (200, 110), (200, 140), (145, 140), (90, 140), (90, 110)] {
            #expect(selected[x * 2, y * 2] == .white, "the handle at \(x), \(y)")
            #expect(final[x * 2 - 100, y * 2 - 120].isNear(Pixel(.red)), "the image at \(x), \(y)")
        }
        // The outline is 3 points outside the bounds: its top line is at y 73, pixel rows 146 and 147.
        // It is thin and dashed: white pixels and blue pixels, and no pixel of the screen (row 9).
        let blue = Pixel(red: 26, green: 140, blue: 255)
        var white = 0, dashes = 0
        for x in 170..<410 {
            for y in [146, 147] {
                if selected[x, y] == .white {
                    white += 1
                } else if selected[x, y].isNear(blue) {
                    dashes += 1
                } else {
                    Issue.record("The pixel \(x), \(y) is not a pixel of the outline: \(selected[x, y])")
                    return
                }
            }
            #expect(selected[x, 145] == patternPixel(x: x, y: 145) && selected[x, 148] == patternPixel(x: x, y: 148))
        }
        #expect(white > 100 && dashes > 100)
        #expect(selected[166, 220].isNear(blue) || selected[166, 220] == .white) // the left line of the outline
        // The image that the file gets has no handle and no outline: it is the same image as before.
        #expect(try differences(from: final) > 1_000)
        #expect(try differences(from: try savedImage()) > 1_000)

        // A drag from its top line, between two handles, moves the mark by 10, 5. The mark, its
        // outline and its handles follow during the drag.
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 115, 80))
        view.mouseDragged(with: try stage.mouse(.leftMouseDragged, 125, 85))
        let during = try stage.renderedPixels()
        #expect(during[200, 250].isNear(Pixel(.red))) // the left line is at x 100 now
        #expect(during[200, 230] == .white && during[420, 290] == .white) // the handles moved with it
        #expect(during[180, 250] == patternPixel(x: 180, y: 250)) // the old place shows the screen again
        // The list of marks changes at the release: one drag is one Undo step.
        #expect(interaction.marks.marks[0].frame == CGRect(x: 40, y: 20, width: 110, height: 60))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 125, 85))
        #expect(interaction.marks.marks[0].frame == CGRect(x: 50, y: 25, width: 110, height: 60))
        #expect(stage.boxRect == selection.rect)

        // Esc clears the selection, and the capture stays open (row 22). With no selected mark,
        // each pixel of the box in the overlay is again the pixel of the image.
        view.keyDown(with: try stage.key(53))
        #expect(interaction.selectedIndex == nil && stage.outcomes.isEmpty && optionsRow.isHidden)
        let moved = try savedImage()
        #expect(try differences(from: moved) == 0)
        #expect(try differences(from: final) > 1_000)

        // A double-click on the text opens its field again, with the old text (row 19).
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 125, 105))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 125, 105))
        #expect(interaction.selectedIndex == 1 && view.textView == nil)
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 125, 105, clicks: 2))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 125, 105))
        field = try #require(view.textView)
        #expect(field.string == "Hello" && panel.firstResponder === field && stage.outcomes.isEmpty)
        #expect(field.selectedRange() == NSRange(location: 5, length: 0))
        // The field is where the text is: from 110, 90 to the right and the bottom edge of the box.
        #expect(field.frame == CGRect(x: 110, y: 140, width: 140, height: 70))
        #expect(field.font?.pointSize == 24)
        // The image below the field has no text now, so the text does not show two times.
        let rectangleOnly = PixelReader(try composeImage(frozen: stage.display, selection: selection, marks: [interaction.marks.marks[0]]))
        #expect(try differences(from: rectangleOnly) == 0)
        // A size button changes the font of the open text (row 18).
        try stage.press("Thin")
        #expect(field.font?.pointSize == 14)
        // Return completes the text: one mark changed, and no mark is new.
        field.insertText(" there", replacementRange: NSRange(location: NSNotFound, length: 0))
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(view.textView == nil && panel.firstResponder === view)
        #expect(interaction.marks.marks.map(\.text) == ["", "Hello there"])
        #expect(interaction.marks.marks[1].style == MarkStyle(color: .red, size: .thin))
        // An empty text removes the mark.
        view.mouseDown(with: try stage.mouse(.leftMouseDown, 125, 98, clicks: 2))
        view.mouseUp(with: try stage.mouse(.leftMouseUp, 125, 98))
        field = try #require(view.textView)
        field.insertText("", replacementRange: NSRange(location: 0, length: 11))
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle] && view.textView == nil)

        // Backspace removes the selected mark (row 16). Then no mark exists, and the box has its handles again.
        try stage.click(at: CGPoint(x: 100, y: 115))
        #expect(interaction.selectedIndex == 0)
        view.keyDown(with: try stage.key(51))
        #expect(interaction.marks.isEmpty && interaction.selectedIndex == nil)
        #expect(try stage.renderedPixels()[100, 120] == .white) // the top-left handle of the box
        // Command-Z puts the mark back, and Delete removes it again after a click.
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: .command)))
        #expect(interaction.marks.marks.map(\.tool) == [.rectangle])
        #expect(try differences(from: PixelReader(try composeFinalImage(frozen: stage.display, selection: selection, marks: interaction.marks))) == 0)
        try stage.click(at: CGPoint(x: 100, y: 115))
        view.keyDown(with: try stage.key(117))
        #expect(interaction.marks.isEmpty)
        #expect(view.performKeyEquivalent(with: try stage.key(6, "z", flags: .command)))

        // Done with a selected mark: the result has the marks at their final places (row 23).
        try stage.click(at: CGPoint(x: 100, y: 115))
        #expect(interaction.selectedMark != nil)
        try stage.press("Done")
        guard case .done(let result)? = stage.outcomes.first, stage.outcomes.count == 1 else {
            Issue.record("Done must report one done")
            return
        }
        #expect(result.marks.marks.map(\.frame) == [CGRect(x: 50, y: 25, width: 110, height: 60)])
    }

    // MARK: The click on a window (YAZ-2769)

    @Test func theWindowBelowThePointerIsBrightWithABlueEdge() async throws {
        let display = try await FakeScreenCapture().freezeAllDisplays()[0]
        // One window: x 20 to 120, y 10 to 70 in points.
        let stage = Stage(display: display, windows: [CGRect(x: 20, y: 10, width: 100, height: 60)])
        let view = stage.view

        view.mouseMoved(with: try stage.mouse(.mouseMoved, 60, 40))
        let bright = try stage.renderedPixels()
        // The window is bright from its first to its last pixel, with no handles. All other areas are dim.
        #expect(bright[40, 20] == patternPixel(x: 40, y: 20))
        #expect(bright[239, 139] == patternPixel(x: 239, y: 139))
        #expect(bright[39, 60].blue > 200 && bright[39, 60].red < 80)
        #expect(bright[300, 180].red < patternPixel(x: 300, y: 180).red)
        #expect(stage.boxRect == nil && view.toolbar.isHidden)

        // The pointer leaves the window: nothing is bright.
        view.mouseMoved(with: try stage.mouse(.mouseMoved, 180, 90))
        let dim = try stage.renderedPixels()
        #expect(dim[100, 60].red < patternPixel(x: 100, y: 60).red)
        #expect(!(dim[39, 60].blue > 200 && dim[39, 60].red < 80))

        // A click on the window: the box is the window, with handles and the toolbar.
        try stage.click(at: CGPoint(x: 60, y: 40))
        #expect(stage.boxRect == CGRect(x: 20, y: 10, width: 100, height: 60))
        #expect(try stage.renderedPixels()[40, 20] == .white)
        #expect(!view.toolbar.isHidden)
    }

    @Test func eachPointerShapeHasACursor() {
        #expect(OverlayView.cursor(for: .crosshair) === NSCursor.crosshair)
        #expect(OverlayView.cursor(for: .openHand) === NSCursor.openHand)
        #expect(OverlayView.cursor(for: .closedHand) === NSCursor.closedHand)
        #expect(OverlayView.cursor(for: .iBeam) === NSCursor.iBeam)
        #expect(OverlayView.cursor(for: .arrow) === NSCursor.arrow)
        // Each handle has its own resize cursor, and it is the same object each time.
        let cursors = Handle.allCases.map { OverlayView.cursor(for: .resize($0)) }
        for (handle, cursor) in zip(Handle.allCases, cursors) {
            #expect(OverlayView.cursor(for: .resize(handle)) === cursor)
            #expect(cursor !== NSCursor.crosshair && cursor !== NSCursor.arrow)
        }
    }

    /// macOS 14 has no diagonal resize cursors, so the app draws them. This Mac never uses that
    /// code, so the test draws the pictures.
    @Test func theResizeCursorsForMacOS14() throws {
        #expect(OverlayView.legacyResizeCursor(for: .left) === NSCursor.resizeLeftRight)
        #expect(OverlayView.legacyResizeCursor(for: .right) === NSCursor.resizeLeftRight)
        #expect(OverlayView.legacyResizeCursor(for: .top) === NSCursor.resizeUpDown)
        #expect(OverlayView.legacyResizeCursor(for: .bottom) === NSCursor.resizeUpDown)

        /// The light pixels (the white edge of the arrow) in the top-left and the top-right corner of the picture.
        func corners(_ handle: Handle) throws -> (topLeft: Int, topRight: Int) {
            let cursor = OverlayView.legacyResizeCursor(for: handle)
            #expect(cursor.hotSpot == CGPoint(x: 9, y: 9))
            let pixels = PixelReader(try #require(cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
            let third = pixels.width / 3
            func light(_ columns: Range<Int>) -> Int {
                var count = 0
                for y in 0..<third {
                    for x in columns where pixels[x, y].red > 200 { count += 1 }
                }
                return count
            }
            return (light(0..<third), light((pixels.width - third)..<pixels.width))
        }
        // The arrow goes from the corner of the handle to the opposite corner.
        for handle in [Handle.topLeft, .bottomRight] {
            let found = try corners(handle)
            #expect(found.topLeft > 5 && found.topRight == 0, "handle \(handle)")
        }
        for handle in [Handle.topRight, .bottomLeft] {
            let found = try corners(handle)
            #expect(found.topRight > 5 && found.topLeft == 0, "handle \(handle)")
        }
    }

    /// YAZ-3148: with no text field open, Command-C, X and V reach the capture. A key that stays
    /// down makes one paste only, and Shift-Command-V is not for the overlay (rows 20 and 21 on YAZ-3150).
    @Test func commandCXAndVCopyCutAndPasteTheSelectedMarkAndAKeyRepeatMakesNoSecondPaste() async throws {
        let stage = try await Stage.retina()
        let view = stage.view, interaction = stage.interaction
        try stage.drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 180, y: 90))
        interaction.selectTool(.rectangle)
        try stage.drag(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 80, y: 50))
        interaction.toggleSelecting()
        try stage.click(at: CGPoint(x: 40, y: 35))
        #expect(interaction.selectedIndex == 0)
        func command(_ keyCode: Int, _ key: String, shift: Bool = false, isARepeat: Bool = false) throws -> Bool {
            let flags: NSEvent.ModifierFlags = shift ? [.command, .shift] : .command
            return view.performKeyEquivalent(with: try stage.key(UInt16(keyCode), key, flags: flags, isARepeat: isARepeat))
        }

        #expect(try command(kVK_ANSI_C, "c"))
        #expect(try command(kVK_ANSI_V, "v"))
        #expect(interaction.marks.marks.count == 2 && interaction.selectedIndex == 1)
        #expect(try command(kVK_ANSI_V, "v", isARepeat: true))
        #expect(interaction.marks.marks.count == 2)
        #expect(try !command(kVK_ANSI_V, "V", shift: true))
        #expect(interaction.marks.marks.count == 2)
        #expect(try command(kVK_ANSI_X, "x"))
        #expect(interaction.marks.marks.count == 1 && interaction.selectedIndex == nil)
    }
}
