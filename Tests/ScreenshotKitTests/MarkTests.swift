import AppKit
@testable import ScreenshotKit
import Testing

@Suite struct MarkListTests {
    private func mark(_ x: CGFloat) -> Mark {
        Mark(tool: .pen, style: .initial(for: .pen), points: [CGPoint(x: x, y: 0), CGPoint(x: x, y: 9)])
    }

    @Test func addUndoAndRedo() {
        var list = MarkList()
        // Undo and Redo with no mark do nothing.
        var worked = list.undo()
        #expect(!worked)
        worked = list.redo()
        #expect(!worked)
        #expect(list.isEmpty && !list.canUndo && !list.canRedo)

        list.add(mark(1))
        list.add(mark(2))
        #expect(list.marks == [mark(1), mark(2)])

        worked = list.undo()
        #expect(worked)
        #expect(list.marks == [mark(1)])
        worked = list.redo()
        #expect(worked)
        #expect(list.marks == [mark(1), mark(2)])
        worked = list.redo()
        #expect(!worked)

        // Two times Undo, then two times Redo: the marks come back in their order.
        list.undo()
        list.undo()
        #expect(list.isEmpty && list.canRedo)
        worked = list.undo()
        #expect(!worked)
        list.redo()
        list.redo()
        #expect(list.marks == [mark(1), mark(2)])

        // A new mark after an Undo clears the Redo list.
        list.undo()
        list.add(mark(3))
        #expect(list.marks == [mark(1), mark(3)])
        worked = list.redo()
        #expect(!worked)
        #expect(list.marks == [mark(1), mark(3)])
    }

    @Test func theStylesOfTheTools() {
        // The first time: Highlight has amber, each other tool has red, and all have Medium.
        for tool in Tool.allCases {
            let expected = MarkStyle(color: tool == .highlight ? .amber : .red, size: .medium)
            #expect(MarkStyle.initial(for: tool) == expected)
            #expect(ToolStyleMemory()[tool] == expected)
        }
        let widths = MarkSize.allCases.map { MarkStyle(color: .red, size: $0).lineWidth(for: .rectangle) }
        #expect(widths == [2, 4, 7])
        let highlightWidths = MarkSize.allCases.map { MarkStyle(color: .red, size: $0).lineWidth(for: .highlight) }
        #expect(highlightWidths == [10, 16, 24])
        #expect(MarkSize.allCases.map { MarkStyle(color: .red, size: $0).fontSize } == [14, 18, 24])
        #expect(Tool.allCases.map(\.name) == ["Rectangle", "Ellipse", "Arrow", "Pen", "Highlight", "Text"])
        #expect(MarkColor.allCases.map(\.name) == ["Red", "Amber", "Green", "Blue", "Black", "White"])
    }
}

/// Each test draws marks through `composeImage`, the code that makes the saved image and the image
/// of the overlay. The box is the full fake screen, so a point of a mark is a point of the image.
@MainActor @Suite struct MarkRendererTests {
    /// The marks on a screen of 60 by 40 points.
    private func render(
        _ marks: [Mark],
        scale: Int = 1,
        background: (_ x: Int, _ y: Int) -> Pixel = { _, _ in .white }
    ) throws -> PixelReader {
        let size = CGSize(width: 60, height: 40)
        let frozen = FrozenDisplay(
            displayID: 7,
            image: makeImage(width: 60 * scale, height: 40 * scale, pixel: background),
            frame: CGRect(origin: .zero, size: size),
            scale: CGFloat(scale)
        )
        let selection = try #require(Selection(rect: CGRect(origin: .zero, size: size), in: size))
        return PixelReader(try composeImage(frozen: frozen, selection: selection, marks: marks))
    }

    private func mark(_ tool: Tool, _ color: MarkColor, _ size: MarkSize, _ points: [CGPoint]) -> Mark {
        Mark(tool: tool, style: MarkStyle(color: color, size: size), points: points)
    }

    /// How many pixels of a row have the colour.
    private func count(_ color: Pixel, in pixels: PixelReader, row y: Int) -> Int {
        (0..<pixels.width).filter { pixels[$0, y].isNear(color) }.count
    }

    @Test func rectangleIsAnOutlineWithNoFill() throws {
        let red = Pixel(.red)
        #expect(red == Pixel(red: 255, green: 59, blue: 48))
        let pixels = try render([mark(.rectangle, .red, .medium, [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30)])])
        #expect(pixels[10, 20].isNear(red)) // the left edge
        #expect(pixels[49, 20].isNear(red)) // the right edge
        #expect(pixels[30, 10].isNear(red)) // the top edge
        #expect(pixels[30, 30].isNear(red)) // the bottom edge
        #expect(pixels[30, 20] == .white) // no fill
        #expect(pixels[3, 3] == .white)
        #expect(pixels[56, 36] == .white)
        // Medium is 4 points: each of the two upright edges is 4 pixels wide in a row.
        #expect(count(red, in: pixels, row: 20) == 8)
        #expect(pixels[8, 20].isNear(red) && pixels[11, 20].isNear(red) && pixels[7, 20] == .white && pixels[12, 20] == .white)
    }

    @Test func aLineOf4PointsIs8PixelsWideAtScale2() throws {
        let red = Pixel(.red)
        let pixels = try render([mark(.rectangle, .red, .medium, [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30)])], scale: 2)
        #expect(pixels.width == 120 && pixels.height == 80)
        // The left edge is at 10 points: pixels 16 to 23. The right edge is at 50 points: pixels 96 to 103.
        let row = (0..<pixels.width).filter { pixels[$0, 40].isNear(red) }
        #expect(row == Array(16...23) + Array(96...103))
        // The top edge is at 10 points: 8 pixel rows, from 16 to 23.
        #expect((0..<pixels.height).filter { pixels[60, $0].isNear(red) } == Array(16...23) + Array(56...63))
    }

    @Test func ellipseIsAnOutlineWithNoFill() throws {
        let blue = Pixel(.blue)
        let pixels = try render([mark(.ellipse, .blue, .thin, [CGPoint(x: 50, y: 30), CGPoint(x: 10, y: 10)])])
        #expect(pixels[10, 20].isNear(blue)) // the left end
        #expect(pixels[49, 20].isNear(blue)) // the right end
        #expect(pixels[30, 10].isNear(blue)) // the top
        #expect(pixels[30, 29].isNear(blue)) // the bottom
        #expect(pixels[30, 20] == .white)
        // An ellipse does not reach the corners of its rectangle.
        #expect(pixels[11, 11] == .white)
        #expect(pixels[48, 28] == .white)
    }

    @Test func arrowIsALineWithAFilledHeadAtItsEnd() throws {
        let green = Pixel(.green)
        func arrow(_ size: MarkSize) -> Mark { mark(.arrow, .green, size, [CGPoint(x: 6, y: 20), CGPoint(x: 54, y: 20)]) }
        let pixels = try render([arrow(.medium)])
        #expect(pixels[15, 20].isNear(green)) // the line
        #expect(pixels[15, 24] == .white) // the line is 4 points wide, so 4 points from its middle is clear
        #expect(pixels[38, 24].isNear(green)) // the head is wider than the line
        #expect(pixels[51, 20].isNear(green)) // near the tip
        #expect(pixels[51, 24] == .white) // the head is narrow at the tip
        #expect(pixels[57, 20] == .white) // the tip is the end of the drag
        #expect(pixels[1, 20] == .white)

        // The head becomes larger with the size: count the green pixels of the column at the base of the head.
        func headHeight(_ size: MarkSize, column: Int) throws -> Int {
            let pixels = try render([arrow(size)])
            return (0..<pixels.height).filter { pixels[column, $0].isNear(green) }.count
        }
        // The heads are 12, 18 and 27 points long. One point after its base, each head is near its full width.
        let thin = try headHeight(.thin, column: 43)
        let medium = try headHeight(.medium, column: 37)
        let thick = try headHeight(.thick, column: 28)
        #expect(thin >= 8 && thin < medium && medium < thick)
    }

    @Test func penIsASmoothFreeLineWithRoundEnds() throws {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 30), CGPoint(x: 30, y: 10), CGPoint(x: 40, y: 30)]
        let pixels = try render([mark(.pen, .black, .thick, points)])
        #expect(pixels[10, 10] == .black) // the start
        #expect(pixels[39, 29] == .black) // the end
        // The line goes through the middle of each segment between two points.
        #expect(pixels[25, 20] == .black)
        #expect(pixels[35, 20] == .black)
        // Smooth: the line does not reach the corner points in the middle of the drag.
        #expect(pixels[20, 30] == .white)
        // Round ends: the line is 7 points wide, and the end goes about 3 points past the last point.
        #expect(pixels[8, 9].red < 60)
        #expect(pixels[40, 32].red < 60)
        #expect(pixels[50, 5] == .white)
    }

    @Test func highlightColoursALightPixelAndLetsADarkPixelStayDark() throws {
        // A white screen with a black bar from x 28 to 31, as text below a highlighter.
        let pixels = try render([mark(.highlight, .amber, .medium, [CGPoint(x: 5, y: 20), CGPoint(x: 55, y: 20)])]) { x, _ in
            (28...31).contains(x) ? .black : .white
        }
        // 40% of amber on white.
        #expect(pixels[15, 20].isNear(Pixel(red: 255, green: 224, blue: 153)))
        #expect(pixels[45, 20].isNear(Pixel(red: 255, green: 224, blue: 153)))
        // The dark pixels below the mark stay dark.
        #expect(pixels[29, 20] == .black)
        #expect(pixels[30, 14] == .black)
        // Medium is 16 points wide: rows 12 to 27.
        #expect((0..<pixels.height).filter { pixels[15, $0] != .white } == Array(12...27))
        #expect(pixels[2, 20] == .white)
    }

    @Test func textIsUprightAtItsPlaceAndBreaksAtItsWidth() throws {
        func isBlue(_ pixel: Pixel) -> Bool { pixel.blue > 200 && pixel.red < 90 }
        let style = MarkStyle(color: .blue, size: .thick)

        // One "L" at x 10, y 5.
        let letter = Mark(tool: .text, style: style, points: [CGPoint(x: 10, y: 5)], text: "L", wrapWidth: 45)
        let pixels = try render([letter])
        var columns: [Int] = [], rows: [Int] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where isBlue(pixels[x, y]) {
                columns.append(x)
                rows.append(y)
            }
        }
        let left = try #require(columns.min()), right = try #require(columns.max())
        let top = try #require(rows.min()), bottom = try #require(rows.max())
        // The letter is where the mark is: right of x 10, below y 5, and one line of 24 points high.
        #expect(left >= 10 && left <= 14)
        #expect(top >= 5 && bottom <= 5 + 30)
        #expect(bottom - top >= 12)
        // Upright: the foot of the "L" is at the bottom, and its stem is at the left.
        let topRow = (left...right).filter { isBlue(pixels[$0, top + 1]) }.count
        let bottomRow = (left...right).filter { isBlue(pixels[$0, bottom - 1]) }.count
        #expect(bottomRow > topRow * 2)
        #expect(isBlue(pixels[left + 1, top + 4]))
        #expect(!isBlue(pixels[right, top + 4]))

        // A long line breaks at the wrap width: more than one line, and nothing right of the width.
        let thin = MarkStyle(color: .blue, size: .thin)
        let long = Mark(tool: .text, style: thin, points: [CGPoint(x: 4, y: 2)], text: "HHH HHH HHH", wrapWidth: 30)
        let wrapped = try render([long])
        var lastColumn = 0, lastRow = 0
        for y in 0..<wrapped.height {
            for x in 0..<wrapped.width where isBlue(wrapped[x, y]) {
                lastColumn = max(lastColumn, x)
                lastRow = max(lastRow, y)
            }
        }
        #expect(lastColumn > 20 && lastColumn < 4 + 30)
        #expect(lastRow > 2 + 20) // a second line exists below the first line of 14 points

        // The overlay field and the renderer use the same layout: its used area has the same lines.
        let layout = TextLayout(text: long.text, style: thin, wrapWidth: 30)
        #expect(layout.usedRect.width <= 30)
        #expect(lastRow <= 2 + Int(layout.usedRect.height.rounded(.up)))
    }

    @Test func marksAreDrawnInTheirOrderAndAnImageWithNoMarkIsOnlyTheCrop() throws {
        // The later mark is above the earlier mark.
        let red = mark(.pen, .red, .thick, [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 20)])
        let black = mark(.pen, .black, .thick, [CGPoint(x: 30, y: 5), CGPoint(x: 30, y: 35)])
        #expect(try render([red, black])[30, 20] == .black)
        #expect(try render([black, red])[30, 20].isNear(Pixel(.red)))
        #expect(try render([])[30, 20] == .white)
    }
}
