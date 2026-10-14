import AppKit
import ImageIO
@testable import ScreenshotKit
import Testing

/// A sound that counts its plays and makes no noise.
private final class CountingSound: SoundPlaying {
    private(set) var plays = 0
    func play() { plays += 1 }
}

/// The end-to-end flow with no window: a fake frozen screen, the pointer calls, a key,
/// and then the same `deliver` call that the app makes.
@Suite struct CaptureFlowTests {
    let day = localDate(year: 2026, month: 10, day: 12)

    /// Runs one capture on the fake screens and returns what it reported.
    private func capture(
        on displayID: CGDirectDisplayID,
        from start: CGPoint,
        to end: CGPoint,
        then key: CaptureKey
    ) async throws -> CaptureOutcome {
        let interaction = CaptureInteraction(displays: try await FakeScreenCapture().freezeAllDisplays())
        var outcome: CaptureOutcome?
        interaction.onFinish = { outcome = $0 }
        interaction.pointerDown(at: start, on: displayID)
        interaction.pointerDragged(to: end)
        interaction.pointerUp(at: end)
        interaction.key(key)
        return try #require(outcome)
    }

    /// The drag goes up and to the left. The box is x 20, y 10, 130 by 60 points.
    /// The test runs for the screen with scale 2 and for the screen with scale 1.
    @Test(arguments: [
        (FakeScreenCapture.retinaID, 2),
        (FakeScreenCapture.plainID, 1),
    ])
    func enterCopiesAndSavesTheBoxAtThePixelsOfItsScreen(displayID: CGDirectDisplayID, scale: Int) async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)

        let outcome = try await capture(
            on: displayID, from: CGPoint(x: 150, y: 70), to: CGPoint(x: 20, y: 10), then: .enter
        )
        try saver.deliver(outcome, date: day)
        saver.waitForPendingWrites()

        // The folder has one file, with the name of the day and the number 1. No temporary file stays.
        #expect(sandbox.fileNames == ["Snip20261012_1.png"])
        let fileData = try Data(contentsOf: sandbox.folder.appendingPathComponent("Snip20261012_1.png"))
        let source = try #require(CGImageSourceCreateWithData(fileData as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        // The size is the box in points multiplied by the scale.
        #expect(image.width == 130 * scale)
        #expect(image.height == 60 * scale)

        // The four corner pixels are the pixels of the frozen image at the corners of the box.
        let pixels = PixelReader(image)
        let left = 20 * scale, top = 10 * scale, right = 150 * scale - 1, bottom = 70 * scale - 1
        #expect(pixels[0, 0] == patternPixel(x: left, y: top))
        #expect(pixels[image.width - 1, 0] == patternPixel(x: right, y: top))
        #expect(pixels[0, image.height - 1] == patternPixel(x: left, y: bottom))
        #expect(pixels[image.width - 1, image.height - 1] == patternPixel(x: right, y: bottom))

        // 72 dpi multiplied by the scale. PNG keeps pixels for each metre, so the value is not exact.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = try #require(properties?[kCGImagePropertyDPIWidth] as? Double)
        #expect(abs(dpi - Double(72 * scale)) < 0.5)

        // The private pasteboard holds the same PNG, and a TIFF for old apps.
        #expect(sandbox.pasteboard.data(forType: .png) == fileData)
        let tiff = try #require(sandbox.pasteboard.data(forType: .tiff))
        let tiffSource = try #require(CGImageSourceCreateWithData(tiff as CFData, nil))
        #expect(CGImageSourceGetType(tiffSource) as String? == "public.tiff")
        let tiffImage = try #require(CGImageSourceCreateImageAtIndex(tiffSource, 0, nil))
        #expect(tiffImage.width == image.width)
        #expect(PixelReader(tiffImage)[0, 0] == patternPixel(x: left, y: top))
    }

    /// The hotkey, pressed again, copies and saves the box, as Enter does.
    @Test func theHotKeyCopiesAndSavesTheBox() async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)

        let outcome = try await capture(
            on: FakeScreenCapture.retinaID, from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70), then: .hotKey
        )
        try saver.deliver(outcome, date: day)
        saver.waitForPendingWrites()

        let saved = try savedImage(in: sandbox)
        #expect(saved.image.width == 260 && saved.image.height == 120)
        #expect(sandbox.pasteboard.data(forType: .png) == saved.data)
    }

    /// YAZ-2866: Done plays the sound one time and still saves. Esc and the switch off play nothing.
    @MainActor
    @Test func theSoundPlaysOnlyForADoneWithTheSwitchOn() async throws {
        let done = try await capture(
            on: FakeScreenCapture.retinaID, from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70), then: .enter
        )
        let cancel = try await capture(
            on: FakeScreenCapture.retinaID, from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70), then: .escape
        )

        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)
        let sound = CountingSound()
        let app = AppController(saver: saver, store: SettingsStore(defaults: MemoryDefaults()), sound: sound)
        app.captureEnded(done)
        #expect(sound.plays == 1)
        app.captureEnded(cancel)
        #expect(sound.plays == 1)
        saver.waitForPendingWrites()
        #expect(sandbox.fileNames.count == 1)
        #expect(sandbox.pasteboard.data(forType: .png) != nil)

        let off = SettingsStore(defaults: MemoryDefaults())
        off.playSound = false
        let silentSound = CountingSound()
        let silentSaver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)
        AppController(saver: silentSaver, store: off, sound: silentSound).captureEnded(done)
        silentSaver.waitForPendingWrites()
        #expect(silentSound.plays == 0)
    }

    /// Reads the one PNG that a capture wrote to the folder of the sandbox.
    private func savedImage(in sandbox: Sandbox) throws -> (image: CGImage, data: Data) {
        #expect(sandbox.fileNames == ["Snip20261012_1.png"])
        let data = try Data(contentsOf: sandbox.folder.appendingPathComponent("Snip20261012_1.png"))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return (try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)), data)
    }

    /// YAZ-2766: drag a box, move it, change its size, press Enter. The PNG has the size of the final box.
    @Test func aBoxThatWasMovedAndResizedIsSavedAtItsFinalSize() async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)
        let interaction = CaptureInteraction(displays: try await FakeScreenCapture().freezeAllDisplays(), styles: ToolStyleMemory())
        var outcome: CaptureOutcome?
        interaction.onFinish = { outcome = $0 }
        let retina = FakeScreenCapture.retinaID
        func drag(from start: CGPoint, to end: CGPoint) {
            interaction.pointerDown(at: start, on: retina)
            interaction.pointerDragged(to: end)
            interaction.pointerUp(at: end)
        }

        drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 100, y: 50)) // the box: 80 by 40 points
        drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 90, y: 40)) // move it by 30, 10: x 50 to 130, y 20 to 60
        drag(from: CGPoint(x: 130, y: 60), to: CGPoint(x: 160, y: 90)) // the bottom-right handle
        drag(from: CGPoint(x: 50, y: 55), to: CGPoint(x: 40, y: 55)) // the left handle
        #expect(interaction.selection(on: retina)?.rect == CGRect(x: 40, y: 20, width: 120, height: 70))
        interaction.key(.enter)

        try saver.deliver(try #require(outcome), date: day)
        saver.waitForPendingWrites()
        let image = try savedImage(in: sandbox).image
        // 120 by 70 points at scale 2.
        #expect(image.width == 240 && image.height == 140)
        let pixels = PixelReader(image)
        #expect(pixels[0, 0] == patternPixel(x: 80, y: 40))
        #expect(pixels[239, 139] == patternPixel(x: 319, y: 179))
    }

    /// YAZ-2767: drag a box, draw a red rectangle, press Enter. The PNG has red pixels on the
    /// rectangle and the original pixels in other places. The test runs at scale 2 and at scale 1.
    @Test(arguments: [
        (FakeScreenCapture.retinaID, 2),
        (FakeScreenCapture.plainID, 1),
    ])
    func aRedRectangleIsInTheSavedImageAtThePixelScaleOfTheScreen(displayID: CGDirectDisplayID, scale: Int) async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)
        let interaction = CaptureInteraction(displays: try await FakeScreenCapture().freezeAllDisplays(), styles: ToolStyleMemory())
        var outcome: CaptureOutcome?
        interaction.onFinish = { outcome = $0 }

        // The box: x 20 to 150, y 10 to 70. The rectangle in it: x 20 to 80, y 10 to 40 of the box.
        interaction.pointerDown(at: CGPoint(x: 20, y: 10), on: displayID)
        interaction.pointerUp(at: CGPoint(x: 150, y: 70))
        interaction.selectTool(.rectangle)
        // Medium: a line of 4 points has whole pixels at each scale. The first size is Thick (7 points).
        interaction.setSize(.medium)
        interaction.pointerDown(at: CGPoint(x: 40, y: 20), on: displayID)
        interaction.pointerDragged(to: CGPoint(x: 70, y: 30))
        interaction.pointerUp(at: CGPoint(x: 100, y: 50))
        interaction.key(.enter)

        try saver.deliver(try #require(outcome), date: day)
        saver.waitForPendingWrites()
        let saved = try savedImage(in: sandbox)
        #expect(saved.image.width == 130 * scale && saved.image.height == 60 * scale)
        let pixels = PixelReader(saved.image)
        let red = Pixel(.red)
        func original(_ x: Int, _ y: Int) -> Pixel { patternPixel(x: 20 * scale + x, y: 10 * scale + y) }

        // The line is 4 points wide: 4 pixels at scale 1 and 8 pixels at scale 2, around each edge.
        let middleRow = 25 * scale
        let redInRow = (0..<pixels.width).filter { pixels[$0, middleRow].isNear(red) }
        #expect(redInRow == Array((18 * scale)..<(22 * scale)) + Array((78 * scale)..<(82 * scale)))
        let middleColumn = 50 * scale
        let redInColumn = (0..<pixels.height).filter { pixels[middleColumn, $0].isNear(red) }
        #expect(redInColumn == Array((8 * scale)..<(12 * scale)) + Array((38 * scale)..<(42 * scale)))

        // Each pixel that is not on the line is the pixel of the frozen image: inside the rectangle
        // (no fill), outside it, and at the four corners of the image.
        var changed = 0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels[x, y] != original(x, y) {
                changed += 1
                let onLineX = (18 * scale..<22 * scale).contains(x) || (78 * scale..<82 * scale).contains(x)
                let onLineY = (8 * scale..<12 * scale).contains(y) || (38 * scale..<42 * scale).contains(y)
                if !(onLineX && (8 * scale..<42 * scale).contains(y)) && !(onLineY && (18 * scale..<82 * scale).contains(x)) {
                    Issue.record("The pixel \(x), \(y) is not on the line, but it changed")
                    return
                }
            }
        }
        #expect(changed > 300 * scale * scale)
        #expect(pixels[0, 0] == original(0, 0))
        #expect(pixels[pixels.width - 1, pixels.height - 1] == original(pixels.width - 1, pixels.height - 1))
        #expect(pixels[middleColumn, middleRow] == original(middleColumn, middleRow))

        // The private pasteboard holds the same PNG.
        #expect(sandbox.pasteboard.data(forType: .png) == saved.data)
    }

    /// YAZ-2841 rows 1.2 and 1.11: select Number, click two times in the box, press Enter. The
    /// PNG has two red circles with white digits at the places of the clicks, and the original
    /// pixels in other places. The test runs at scale 2 and at scale 1.
    @Test(arguments: [
        (FakeScreenCapture.retinaID, 2),
        (FakeScreenCapture.plainID, 1),
    ])
    func twoNumbersAreInTheSavedImageAtThePixelScaleOfTheScreen(displayID: CGDirectDisplayID, scale: Int) async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)
        let interaction = CaptureInteraction(displays: try await FakeScreenCapture().freezeAllDisplays(), styles: ToolStyleMemory())
        var outcome: CaptureOutcome?
        interaction.onFinish = { outcome = $0 }

        // The box: x 20 to 150, y 10 to 70. The numbers: Thick (40 points), with their middles
        // at x 40 and x 100, y 30 of the box.
        interaction.pointerDown(at: CGPoint(x: 20, y: 10), on: displayID)
        interaction.pointerUp(at: CGPoint(x: 150, y: 70))
        interaction.selectTool(.number)
        for x: CGFloat in [60, 120] {
            interaction.pointerDown(at: CGPoint(x: x, y: 40), on: displayID)
            interaction.pointerUp(at: CGPoint(x: x, y: 40))
        }
        interaction.key(.enter)

        try saver.deliver(try #require(outcome), date: day)
        saver.waitForPendingWrites()
        let saved = try savedImage(in: sandbox)
        #expect(saved.image.width == 130 * scale && saved.image.height == 60 * scale)
        let pixels = PixelReader(saved.image)
        let red = Pixel(.red)
        func original(_ x: Int, _ y: Int) -> Pixel { patternPixel(x: 20 * scale + x, y: 10 * scale + y) }
        func at(_ x: Int, _ y: Int) -> Pixel { pixels[x * scale, y * scale] }

        let middles = [CGPoint(x: 40, y: 30), CGPoint(x: 100, y: 30)]
        // For each number: the places of its white pixels, from the top-left of its digit area.
        var digits: [Set<[Int]>] = []
        for middle in middles {
            let x = Int(middle.x), y = Int(middle.y)
            // The circle: red at the left of the digit, above it and below it.
            #expect(at(x - 15, y).isNear(red) && at(x, y - 17).isNear(red) && at(x, y + 16).isNear(red), "\(middle)")
            // Just outside the circle: the frozen image.
            #expect(at(x - 21, y) == original((x - 21) * scale, y * scale), "\(middle)")
            // The digit: white pixels in the middle of the circle. The pattern has no white pixel.
            var white = Set<[Int]>()
            for row in ((y - 12) * scale)..<((y + 12) * scale) {
                for column in ((x - 12) * scale)..<((x + 12) * scale) where pixels[column, row].isNear(.white, tolerance: 10) {
                    white.insert([column - (x - 12) * scale, row - (y - 12) * scale])
                }
            }
            #expect(white.count > 40 * scale * scale, "\(middle): \(white.count) white pixels")
            digits.append(white)
        }
        // The digits of 1 and of 2 differ, and the digit 2 has more pixels than the digit 1.
        #expect(digits[0] != digits[1] && digits[1].count > digits[0].count)

        // Each pixel that changed is in one of the two circles (with 1 point for the soft edge).
        var changed = 0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels[x, y] != original(x, y) {
                changed += 1
                let point = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(scale), y: (CGFloat(y) + 0.5) / CGFloat(scale))
                if !middles.contains(where: { hypot(point.x - $0.x, point.y - $0.y) <= 21 }) {
                    Issue.record("The pixel \(x), \(y) is not in a circle, but it changed")
                    return
                }
            }
        }
        // Two circles of 20 points: about 2 x 1257 points.
        #expect(changed > 2400 * scale * scale)
        #expect(pixels[0, 0] == original(0, 0) && at(70, 30) == original(70 * scale, 30 * scale))

        // The private pasteboard holds the same PNG.
        #expect(sandbox.pasteboard.data(forType: .png) == saved.data)
    }

    /// YAZ-2782: draw a red rectangle, move it with "Select", press Enter while it is still selected.
    /// The PNG has the red pixels at the new place and the original pixels at the old place, and
    /// it has no outline and no handle. The test runs at scale 2 and at scale 1.
    @Test(arguments: [
        (FakeScreenCapture.retinaID, 2),
        (FakeScreenCapture.plainID, 1),
    ])
    func aRectangleThatWasMovedWithSelectIsSavedAtItsNewPlaceWithNoOutline(displayID: CGDirectDisplayID, scale: Int) async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)
        let interaction = CaptureInteraction(displays: try await FakeScreenCapture().freezeAllDisplays(), styles: ToolStyleMemory())
        var outcome: CaptureOutcome?
        interaction.onFinish = { outcome = $0 }

        // The box: x 20 to 150, y 10 to 70. The rectangle in it: x 20 to 80, y 10 to 40 of the box.
        interaction.pointerDown(at: CGPoint(x: 20, y: 10), on: displayID)
        interaction.pointerUp(at: CGPoint(x: 150, y: 70))
        interaction.selectTool(.rectangle)
        // Medium: a line of 4 points has whole pixels at each scale.
        interaction.setSize(.medium)
        interaction.pointerDown(at: CGPoint(x: 40, y: 20), on: displayID)
        interaction.pointerUp(at: CGPoint(x: 100, y: 50))

        // "Select": a drag from the left line of the rectangle moves it by 30, 10.
        // Now it is x 50 to 110, y 20 to 50 of the box.
        interaction.toggleSelecting()
        interaction.pointerDown(at: CGPoint(x: 40, y: 35), on: displayID)
        interaction.pointerDragged(to: CGPoint(x: 55, y: 40))
        interaction.pointerUp(at: CGPoint(x: 70, y: 45))
        #expect(interaction.marks.marks.map(\.frame) == [CGRect(x: 50, y: 20, width: 60, height: 30)])
        // The mark is still selected, so the overlay shows its outline and its eight handles now.
        #expect(interaction.selectedMark?.handles.count == 8)
        #expect(interaction.selection(on: displayID)?.rect == CGRect(x: 20, y: 10, width: 130, height: 60))
        interaction.key(.enter)

        try saver.deliver(try #require(outcome), date: day)
        saver.waitForPendingWrites()
        let saved = try savedImage(in: sandbox)
        #expect(saved.image.width == 130 * scale && saved.image.height == 60 * scale)
        let pixels = PixelReader(saved.image)
        let red = Pixel(.red)

        // The line is 4 points wide around the rectangle at its new place.
        func isOnTheLine(_ x: Int, _ y: Int) -> Bool {
            let isInOuterEdge = (48 * scale..<112 * scale).contains(x) && (18 * scale..<52 * scale).contains(y)
            let isInInnerEdge = (52 * scale..<108 * scale).contains(x) && (22 * scale..<48 * scale).contains(y)
            return isInOuterEdge && !isInInnerEdge
        }
        // Each pixel on the line is red. Each other pixel is the pixel of the frozen image: the
        // old place of the rectangle, the place of the outline, and the places of the handles.
        var redPixels = 0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                if isOnTheLine(x, y) {
                    redPixels += 1
                    if !pixels[x, y].isNear(red) {
                        Issue.record("The pixel \(x), \(y) is on the line, but it is \(pixels[x, y])")
                        return
                    }
                } else if pixels[x, y] != patternPixel(x: 20 * scale + x, y: 10 * scale + y) {
                    Issue.record("The pixel \(x), \(y) is not on the line, but it changed to \(pixels[x, y])")
                    return
                }
            }
        }
        #expect(redPixels == 720 * scale * scale) // 64 by 34 points without the inside of 56 by 26 points
        // The old place: the middle of its left line and its top-left corner.
        #expect(pixels[20 * scale, 25 * scale] == patternPixel(x: 40 * scale, y: 35 * scale))
        #expect(pixels[20 * scale, 10 * scale] == patternPixel(x: 40 * scale, y: 20 * scale))
        // The private pasteboard holds the same PNG.
        #expect(sandbox.pasteboard.data(forType: .png) == saved.data)
    }

    @Test func escGivesACancelNoFileAndAnEmptyPasteboard() async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)

        // A box exists already when Esc comes. It still must not be saved.
        let outcome = try await capture(
            on: FakeScreenCapture.retinaID, from: CGPoint(x: 20, y: 10), to: CGPoint(x: 150, y: 70), then: .escape
        )
        guard case .cancel = outcome else {
            Issue.record("Esc must report a cancel")
            return
        }
        try saver.deliver(outcome, date: day)
        saver.waitForPendingWrites()

        #expect(sandbox.fileNames.isEmpty)
        #expect(sandbox.pasteboard.pasteboardItems?.isEmpty ?? true)
        #expect(sandbox.pasteboard.data(forType: .png) == nil)
    }

    @Test func aSaveNeverWritesOverAFile() async throws {
        let sandbox = try Sandbox()
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: sandbox.folder)
        let old = Data("a file from Snip".utf8)
        let oldURL = sandbox.folder.appendingPathComponent("Snip20261012_7.png")
        try old.write(to: oldURL)

        // Two captures in a row continue after the highest number.
        let image = makePatternImage(width: 8, height: 8)
        try saver.save(image, scale: 1, date: day)
        try saver.save(image, scale: 1, date: day)
        saver.waitForPendingWrites()
        #expect(sandbox.fileNames == ["Snip20261012_7.png", "Snip20261012_8.png", "Snip20261012_9.png"])
        #expect(try Data(contentsOf: oldURL) == old)

        // The race: a different app took the name after the app read the folder.
        // The move must refuse, and the file that exists must stay.
        let temporary = sandbox.folder.appendingPathComponent(".Snip-test.tmp")
        try Data("new".utf8).write(to: temporary)
        #expect(try ScreenshotSaver.moveWithoutOverwrite(temporary, to: oldURL) == false)
        #expect(try Data(contentsOf: oldURL) == old)
        #expect(try ScreenshotSaver.moveWithoutOverwrite(temporary, to: sandbox.folder.appendingPathComponent("free.png")))
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test func aMissingFolderKeepsTheImageOnThePasteboardAndReportsTheFolder() async throws {
        let sandbox = try Sandbox()
        let missing = sandbox.folder.appendingPathComponent("missing")
        let saver = ScreenshotSaver(pasteboard: sandbox.pasteboard, folder: missing)

        // The file result comes on the main queue, after the copy to the pasteboard.
        let result: Result<URL, ScreenshotSaver.FileFailure> = try await withCheckedThrowingContinuation { continuation in
            do {
                try saver.save(makePatternImage(width: 8, height: 8), scale: 2, date: day) {
                    continuation.resume(returning: $0)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard case .failure(let failure) = result else {
            Issue.record("A missing folder must report a failure")
            return
        }
        #expect(failure.folder == missing)
        #expect(sandbox.pasteboard.data(forType: .png) == failure.png)
        #expect(sandbox.fileNames.isEmpty)

        // "Choose folder…": the app sets a new folder and writes the PNG that the failure kept.
        saver.folder = sandbox.folder
        saver.writeFile(failure.png, date: failure.date)
        saver.waitForPendingWrites()
        #expect(sandbox.fileNames == ["Snip20261012_1.png"])
        #expect(try Data(contentsOf: sandbox.folder.appendingPathComponent("Snip20261012_1.png")) == failure.png)
    }
}
