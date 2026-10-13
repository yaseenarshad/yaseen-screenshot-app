import CoreGraphics
import ScreenshotKit
import Testing

/// The rules of "click a window to select it" (YAZ-2769), with a fixed window list.
@Suite struct WindowSnapTests {
    /// The main display is 1000 by 800 points. One screen is to the left of it, and one is above it.
    /// These are AppKit frames: the origin is the bottom-left of the main display, and y goes up.
    let main = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let left = CGRect(x: -500, y: 100, width: 500, height: 400)
    let above = CGRect(x: 0, y: 800, width: 1000, height: 600)

    @Test func theTopWindowAtAPoint() {
        let front = CGRect(x: 20, y: 10, width: 100, height: 60)
        let back = CGRect(x: 60, y: 30, width: 120, height: 60)
        // Two windows overlap: the first of the list is in front.
        #expect(WindowSnap.topFrame(in: [front, back], at: CGPoint(x: 80, y: 40)) == front)
        #expect(WindowSnap.topFrame(in: [back, front], at: CGPoint(x: 80, y: 40)) == back)
        #expect(WindowSnap.topFrame(in: [front, back], at: CGPoint(x: 150, y: 80)) == back)
        // No window at the point.
        #expect(WindowSnap.topFrame(in: [front, back], at: CGPoint(x: 190, y: 5)) == nil)
        #expect(WindowSnap.topFrame(in: [], at: CGPoint(x: 80, y: 40)) == nil)
    }

    @Test func smallWindowsOtherLayersAndTheWindowsOfThisAppAreNotInTheList() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let normal = WindowInfo(frame: frame, layer: 0, ownerPID: 50)
        let smallest = WindowInfo(frame: CGRect(x: 0, y: 0, width: 40, height: 40), layer: 0, ownerPID: 51)
        let windows = [
            WindowInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), layer: 0, ownerPID: 99), // an overlay window of this app
            WindowInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 24), layer: 24, ownerPID: 10), // the menu bar
            WindowInfo(frame: CGRect(x: 200, y: 730, width: 600, height: 70), layer: 20, ownerPID: 11), // the Dock
            WindowInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), layer: -2_147_483_603, ownerPID: 12), // the desktop
            normal,
            WindowInfo(frame: CGRect(x: 0, y: 0, width: 39, height: 300), layer: 0, ownerPID: 50), // too narrow
            WindowInfo(frame: CGRect(x: 0, y: 0, width: 300, height: 39), layer: 0, ownerPID: 50), // too low
            WindowInfo(frame: frame, layer: 0, ownerPID: 50, alpha: 0), // invisible
            smallest,
        ]
        // The order stays: from the front to the back.
        #expect(WindowSnap.selectableFrames(of: windows, excludingPID: 99) == [normal.frame, smallest.frame])
    }

    @Test func theCoordinatesChangeForAScreenToTheLeftOfAndAboveTheMainDisplay() {
        // Core Graphics counts from the top-left of the main display, and y goes down.
        #expect(WindowSnap.globalFrame(ofScreen: main, mainDisplayHeight: 800) == CGRect(x: 0, y: 0, width: 1000, height: 800))
        let leftGlobal = WindowSnap.globalFrame(ofScreen: left, mainDisplayHeight: 800)
        #expect(leftGlobal == CGRect(x: -500, y: 300, width: 500, height: 400))
        let aboveGlobal = WindowSnap.globalFrame(ofScreen: above, mainDisplayHeight: 800)
        #expect(aboveGlobal == CGRect(x: 0, y: -600, width: 1000, height: 600))

        // A window on each screen, in the points of that screen (top-left origin).
        #expect(WindowSnap.frames([CGRect(x: -400, y: 350, width: 200, height: 100)], onScreen: leftGlobal)
            == [CGRect(x: 100, y: 50, width: 200, height: 100)])
        #expect(WindowSnap.frames([CGRect(x: 100, y: -500, width: 300, height: 200)], onScreen: aboveGlobal)
            == [CGRect(x: 100, y: 100, width: 300, height: 200)])
    }

    @Test func aWindowThatIsPartlyOnADifferentScreenIsCutToTheScreen() {
        let leftGlobal = WindowSnap.globalFrame(ofScreen: left, mainDisplayHeight: 800)
        let mainGlobal = WindowSnap.globalFrame(ofScreen: main, mainDisplayHeight: 800)
        // 300 points wide: 100 points on the left screen and 200 points on the main display.
        let onTwoScreens = CGRect(x: -100, y: 400, width: 300, height: 200)
        #expect(WindowSnap.frames([onTwoScreens], onScreen: leftGlobal) == [CGRect(x: 400, y: 100, width: 100, height: 200)])
        #expect(WindowSnap.frames([onTwoScreens], onScreen: mainGlobal) == [CGRect(x: 0, y: 400, width: 200, height: 200)])

        // Partly below the main display: cut at the bottom edge.
        #expect(WindowSnap.frames([CGRect(x: 600, y: 700, width: 300, height: 300)], onScreen: mainGlobal)
            == [CGRect(x: 600, y: 700, width: 300, height: 100)])
        // A window of a different screen is not in the list of this screen. The order of the others stays.
        let onMainOnly = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(WindowSnap.frames([onMainOnly, onTwoScreens], onScreen: leftGlobal) == [CGRect(x: 400, y: 100, width: 100, height: 200)])
        // Less than 4 points of a window on this screen: not in the list.
        #expect(WindowSnap.frames([CGRect(x: -2, y: 400, width: 300, height: 200)], onScreen: leftGlobal).isEmpty)
    }

    @Test func aCaptureGetsTheFramesOfEachScreenFromTheWindowList() {
        func display(_ id: CGDirectDisplayID, _ frame: CGRect) -> FrozenDisplay {
            FrozenDisplay(displayID: id, image: makePatternImage(width: 2, height: 2), frame: frame, scale: 1)
        }
        // The main display is not the first of the list. It is the one with the origin 0, 0.
        let displays = [display(3, left), display(1, main), display(2, above)]
        let windows = [
            WindowInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), layer: 0, ownerPID: 99), // this app
            WindowInfo(frame: CGRect(x: -100, y: 400, width: 300, height: 200), layer: 0, ownerPID: 50),
            WindowInfo(frame: CGRect(x: 100, y: -500, width: 300, height: 200), layer: 0, ownerPID: 51),
            WindowInfo(frame: CGRect(x: 50, y: 450, width: 600, height: 300), layer: 0, ownerPID: 52),
        ]
        let frames = WindowSnap.framesByDisplay(windows: windows, displays: displays, excludingPID: 99)
        #expect(frames[3] == [CGRect(x: 400, y: 100, width: 100, height: 200)])
        #expect(frames[1] == [CGRect(x: 0, y: 400, width: 200, height: 200), CGRect(x: 50, y: 450, width: 600, height: 300)])
        #expect(frames[2] == [CGRect(x: 100, y: 100, width: 300, height: 200)])

        // The capture uses them: a click on the main display selects the window in front.
        let interaction = CaptureInteraction(displays: displays, windows: frames, styles: ToolStyleMemory())
        interaction.pointerDown(at: CGPoint(x: 100, y: 500), on: 1)
        interaction.pointerUp(at: CGPoint(x: 100, y: 500))
        #expect(interaction.selection(on: 1)?.rect == CGRect(x: 0, y: 400, width: 200, height: 200))
    }
}
