import AppKit
@testable import ScreenshotKit
import Testing

/// The view adapter, with no window. The test hands `NSEvent` objects to the view (it posts no
/// event to macOS) and draws the layer tree into a bitmap.
@MainActor @Suite struct OverlayViewTests {
    let display: FrozenDisplay // 200 x 100 points at scale 2
    let interaction: CaptureInteraction
    let view: OverlayView

    init() async throws {
        let displays = try await FakeScreenCapture().freezeAllDisplays()
        let interaction = CaptureInteraction(displays: displays)
        let view = OverlayView(display: displays[0], interaction: interaction)
        // The work of `CaptureSession`.
        interaction.onChange = { view.refresh() }
        self.display = displays[0]
        self.interaction = interaction
        self.view = view
    }

    /// A mouse event at a point with a top-left origin. AppKit itself counts from the bottom.
    private func mouse(_ type: NSEvent.EventType, x: CGFloat, yFromTop: CGFloat, clicks: Int = 1) throws -> NSEvent {
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

    private func key(_ keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    /// What the overlay shows, in the pixels of the display (top-left origin).
    private func renderedPixels() throws -> PixelReader {
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
        try #require(view.layer).render(in: context)
        return PixelReader(try #require(context.makeImage()))
    }

    @Test func aMouseDragMakesTheBoxAndTheOverlayShowsIt() throws {
        // Before a drag, the full screen is dim: each pixel is darker than the frozen image.
        let before = try renderedPixels()
        #expect(before[60, 40].red < patternPixel(x: 60, y: 40).red)
        #expect(before[60, 40].green < patternPixel(x: 60, y: 40).green)

        view.mouseDown(with: try mouse(.leftMouseDown, x: 20, yFromTop: 10))
        view.mouseDragged(with: try mouse(.leftMouseDragged, x: 150, yFromTop: 70))
        view.mouseUp(with: try mouse(.leftMouseUp, x: 150, yFromTop: 70))
        #expect(interaction.selection(on: display.displayID)?.rect == CGRect(x: 20, y: 10, width: 130, height: 60))

        // The box is x 40 to 300 and y 20 to 140 in pixels. In the box, the overlay shows the frozen
        // image exactly: upright, and not dim. That includes the first and the last pixel of the box.
        let after = try renderedPixels()
        #expect(after[40, 20] == patternPixel(x: 40, y: 20))
        #expect(after[299, 139] == patternPixel(x: 299, y: 139))
        #expect(after[60, 40] == patternPixel(x: 60, y: 40))
        // The border is the 1 point outside the box, and it is blue.
        #expect(after[39, 60].blue > 200)
        #expect(after[39, 60].red < 80)
        // Away from the box, the screen is still dim.
        #expect(after[350, 180].red < patternPixel(x: 350, y: 180).red)
        #expect(after[350, 180].green < patternPixel(x: 350, y: 180).green)
    }

    @Test func enterEscAndTheMouseButtonsReachTheInteraction() throws {
        var outcomes: [CaptureOutcome] = []
        interaction.onFinish = { outcomes.append($0) }

        view.keyDown(with: try key(36)) // Return with no box: nothing
        view.keyDown(with: try key(0)) // the key A: nothing
        #expect(outcomes.isEmpty)

        view.mouseDown(with: try mouse(.leftMouseDown, x: 20, yFromTop: 10))
        view.mouseDragged(with: try mouse(.leftMouseDragged, x: 150, yFromTop: 70))
        view.mouseUp(with: try mouse(.leftMouseUp, x: 150, yFromTop: 70))

        // A right-click removes the box.
        view.rightMouseDown(with: try mouse(.rightMouseDown, x: 5, yFromTop: 5))
        #expect(interaction.selection(on: display.displayID) == nil)
        #expect(outcomes.isEmpty)

        // A new box, then a double-click in it: done.
        view.mouseDown(with: try mouse(.leftMouseDown, x: 20, yFromTop: 10))
        view.mouseDragged(with: try mouse(.leftMouseDragged, x: 150, yFromTop: 70))
        view.mouseUp(with: try mouse(.leftMouseUp, x: 150, yFromTop: 70))
        view.mouseDown(with: try mouse(.leftMouseDown, x: 30, yFromTop: 20))
        view.mouseUp(with: try mouse(.leftMouseUp, x: 30, yFromTop: 20))
        #expect(outcomes.isEmpty)
        view.mouseDown(with: try mouse(.leftMouseDown, x: 30, yFromTop: 20, clicks: 2))
        guard case .done(let result)? = outcomes.first, outcomes.count == 1 else {
            Issue.record("A double-click in the box must report one done")
            return
        }
        #expect(result.selection.rect == CGRect(x: 20, y: 10, width: 130, height: 60))
    }

    @Test func escCancels() throws {
        var outcomes: [CaptureOutcome] = []
        interaction.onFinish = { outcomes.append($0) }
        view.keyDown(with: try key(53))
        guard case .cancel? = outcomes.first, outcomes.count == 1 else {
            Issue.record("Esc must report one cancel")
            return
        }
    }
}
