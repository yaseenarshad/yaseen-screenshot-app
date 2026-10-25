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

    /// YAZ-2782 row 20: Undo and Redo of a move, a size change, a style change and a delete.
    @Test func undoAndRedoOfAMoveASizeChangeAStyleChangeAndADelete() {
        let box = CGSize(width: 100, height: 60)
        let rectangle = Mark(
            tool: .rectangle, style: MarkStyle(color: .red, size: .medium), points: [CGPoint(x: 20, y: 10), CGPoint(x: 60, y: 40)]
        )
        var blue = rectangle.resized(.frame(.right), to: CGPoint(x: 80, y: 0), in: box).moved(by: CGPoint(x: 5, y: 5), in: box)
        blue.style.color = .blue

        var list = MarkList()
        var states = [list.marks]
        func record(_ list: MarkList) { states.append(list.marks) }
        list.add(rectangle)
        record(list)
        list.add(mark(7))
        record(list)
        var changed = list.replace(at: 0, with: rectangle.moved(by: CGPoint(x: 5, y: 5), in: box)) // a move
        #expect(changed)
        record(list)
        changed = list.replace(at: 0, with: list.marks[0].resized(.frame(.right), to: CGPoint(x: 85, y: 0), in: box)) // a size change
        #expect(changed)
        record(list)
        changed = list.replace(at: 0, with: blue) // a style change
        #expect(changed)
        record(list)
        list.remove(at: 0) // a delete
        record(list)
        #expect(list.marks == [mark(7)])
        #expect(Set(states.map(\.count)) == [0, 1, 2] && states[4] != states[3] && states[5] != states[4])

        // Each Undo takes back one change, down to the empty list. Each Redo puts one back.
        for step in (0..<6).reversed() {
            let worked = list.undo()
            #expect(worked && list.marks == states[step], "undo to state \(step)")
        }
        var worked = list.undo()
        #expect(!worked && list.isEmpty && !list.canUndo && list.canRedo)
        for step in 1...6 {
            worked = list.redo()
            #expect(worked && list.marks == states[step], "redo to state \(step)")
        }
        worked = list.redo()
        #expect(!worked)

        // A change that changes nothing is no Undo step, and a place that does not exist changes nothing.
        let before = list
        changed = list.replace(at: 0, with: mark(7))
        #expect(!changed && list == before)
        changed = list.replace(at: 5, with: rectangle)
        list.remove(at: 5)
        #expect(!changed && list == before)

        // A change after an Undo clears the Redo list.
        list.undo() // the delete: the blue rectangle is back
        #expect(list.marks == [blue, mark(7)] && list.canRedo)
        list.remove(at: 1)
        #expect(list.marks == [blue] && !list.canRedo)
        // The box changed: the list forgets its changes, and keeps its marks.
        list.clearHistory()
        worked = list.undo()
        #expect(!worked && !list.canUndo && list.marks == [blue])
    }

    @Test func theStylesOfTheTools() {
        // The first time: Highlight has amber, each other tool has red, and all have Thick (D15 on YAZ-2782).
        for tool in Tool.allCases {
            let expected = MarkStyle(color: tool == .highlight ? .amber : .red, size: .thick)
            #expect(MarkStyle.initial(for: tool) == expected)
            #expect(ToolStyleMemory()[tool] == expected)
        }
        let widths = MarkSize.allCases.map { MarkStyle(color: .red, size: $0).lineWidth(for: .rectangle) }
        #expect(widths == [2, 4, 7])
        let highlightWidths = MarkSize.allCases.map { MarkStyle(color: .red, size: $0).lineWidth(for: .highlight) }
        #expect(highlightWidths == [10, 16, 24])
        #expect(MarkSize.allCases.map { MarkStyle(color: .red, size: $0).fontSize } == [14, 18, 24])
        #expect(Tool.allCases.map(\.name) == ["Rectangle", "Ellipse", "Arrow", "Pen", "Highlight", "Text", "Number"])
        #expect(MarkColor.allCases.map(\.name) == ["Red", "Amber", "Green", "Blue", "Black", "White"])
        // The circle of a Number mark (YAZ-2841 row 1.9).
        #expect(MarkSize.allCases.map { MarkStyle(color: .red, size: $0).numberDiameter } == [22, 30, 40])
    }

    /// YAZ-2841 rows 1.4 to 1.6: the next number is the highest number in the box, plus 1.
    @Test func theNextNumberIsTheHighestNumberPlusOne() {
        func number(_ value: Int) -> Mark {
            Mark(tool: .number, style: .initial(for: .number), points: [CGPoint(x: value * 10, y: 20)], number: value)
        }
        var list = MarkList()
        #expect(list.nextNumber == 1)
        // A mark of a different tool does not count.
        list.add(mark(1))
        #expect(list.nextNumber == 1)
        for value in 1...3 {
            list.add(number(list.nextNumber))
            #expect(list.marks.last?.number == value)
        }
        #expect(list.nextNumber == 4)

        // Undo of number 3: the next number is 3 again. Redo brings 3 back.
        list.undo()
        #expect(list.nextNumber == 3)
        list.redo()
        #expect(list.nextNumber == 4 && list.marks.last == number(3))

        // Delete of number 2 of 1 to 5: no renumber, and the next number is 6.
        list.add(number(4))
        list.add(number(5))
        list.remove(at: 2) // the pen mark is at 0, so number 2 is at 2
        #expect(list.marks.map(\.number) == [0, 1, 3, 4, 5])
        #expect(list.marks.dropFirst() == [number(1), number(3), number(4), number(5)])
        #expect(list.nextNumber == 6)
        // Undo of the delete puts 2 back at its place in the order.
        list.undo()
        #expect(list.marks.map(\.number) == [0, 1, 2, 3, 4, 5] && list.nextNumber == 6)
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

    /// YAZ-2841 row 1.10: a filled circle in the colour of the mark, with bold digits in its
    /// middle. White digits on red, blue and black. Black digits on amber, green and white.
    @Test func aNumberIsAFilledCircleWithDigitsInAColourThatIsEasyToRead() throws {
        // A grey screen, so a white circle and a black circle both show.
        let grey = Pixel(red: 128, green: 128, blue: 128)
        for color in MarkColor.allCases {
            let digit: Pixel = [.red, .blue, .black].contains(color) ? .white : .black
            for scale in [1, 2] {
                // Thick is 40 points: the circle fills the screen of 60 by 40 points from top to bottom.
                let number = Mark(tool: .number, style: MarkStyle(color: color, size: .thick), points: [CGPoint(x: 30, y: 20)], number: 8)
                let pixels = try render([number], scale: scale, background: { _, _ in grey })
                func at(_ x: CGFloat, _ y: CGFloat) -> Pixel { pixels[Int(x * CGFloat(scale)), Int(y * CGFloat(scale))] }
                let name = "\(color.name) at scale \(scale)"
                // The circle, at the left of the digit and above it. Outside the circle: the screen.
                #expect(at(14, 20).isNear(Pixel(color)) && at(30, 3).isNear(Pixel(color)), "\(name)")
                #expect(at(2, 2) == grey && at(57, 37) == grey && at(8, 20) == grey, "\(name)")
                // The digit: many pixels of the digit colour, all in the middle of the circle.
                var digitPixels = 0
                for y in 0..<pixels.height {
                    for x in 0..<pixels.width where pixels[x, y].isNear(digit, tolerance: 10) {
                        digitPixels += 1
                        let dx = CGFloat(x) / CGFloat(scale) - 30, dy = CGFloat(y) / CGFloat(scale) - 20
                        #expect(abs(dx) < 10 && abs(dy) < 13, "\(name): a digit pixel at \(x), \(y)")
                    }
                }
                // An "8" in a font of 24 points is about 14 by 17 points, with thick strokes.
                #expect(digitPixels > 60 * scale * scale, "\(name): \(digitPixels) digit pixels")
                // The middle of an "8" is on the digit, between its two loops.
                #expect(at(30, 20).isNear(digit, tolerance: 60), "\(name): \(at(30, 20))")
            }
        }
        #expect(MarkRenderer.digitColor(on: .amber) == CGColor(gray: 0, alpha: 1))
        #expect(MarkRenderer.digitColor(on: .blue) == CGColor(gray: 1, alpha: 1))
    }

    /// YAZ-2841 row 1.10: a long number gets smaller, so it stays in 70% of the circle.
    @Test func aLongNumberStaysInsideTheCircle() throws {
        let red = Pixel(.red)
        // A grey screen: white digits outside the circle would show on it.
        let grey = Pixel(red: 128, green: 128, blue: 128)
        for number in [128, 99_999] {
            // Thin is 22 points: 70% is 15.4 points.
            let mark = Mark(tool: .number, style: MarkStyle(color: .red, size: .thin), points: [CGPoint(x: 30, y: 20)], number: number)
            let pixels = try render([mark], scale: 2, background: { _, _ in grey })
            var digitColumns = Set<Int>()
            for y in 0..<pixels.height {
                for x in 0..<pixels.width {
                    let dx = CGFloat(x) / 2 + 0.25 - 30, dy = CGFloat(y) / 2 + 0.25 - 20
                    let distance = hypot(dx, dy)
                    if distance > 12 {
                        // Outside the circle: no digit and no red.
                        #expect(pixels[x, y] == grey, "\(number): \(x), \(y)")
                    } else if distance < 10.5, !pixels[x, y].isNear(red, tolerance: 10) {
                        // A pixel in the circle that is not red is a part of the digits.
                        digitColumns.insert(x)
                    }
                }
            }
            // The digits are 15.4 points wide at most: 31 pixels, in the middle of the circle.
            let width = (digitColumns.max() ?? 0) - (digitColumns.min() ?? 0) + 1
            #expect(width > 20 && width <= 32, "\(number): \(width) pixels wide")
            #expect(abs(CGFloat((digitColumns.max() ?? 0) + (digitColumns.min() ?? 0)) / 2 - 60) <= 2, "\(number)")
        }
    }

    /// The timing check of YAZ-2841: the overlay makes this image again at each move of a drag.
    /// It compares 100 Number marks with 100 rectangles, on a box of 1000 by 600 points at scale 2.
    @Test func theTimeToComposeOneHundredNumbers() throws {
        let size = CGSize(width: 1000, height: 600)
        let frozen = FrozenDisplay(
            displayID: 7, image: makeImage(width: 2000, height: 1200) { _, _ in .white },
            frame: CGRect(origin: .zero, size: size), scale: 2
        )
        let selection = try #require(Selection(rect: CGRect(origin: .zero, size: size), in: size))
        let places = (0..<100).map { (index: Int) -> CGPoint in
            CGPoint(x: 50 + CGFloat(index % 10) * 90, y: 50 + CGFloat(index / 10) * 55)
        }
        let numbers = places.enumerated().map { index, place in
            Mark(tool: .number, style: MarkStyle(color: .red, size: .thick), points: [place], number: index + 1)
        }
        let rectangles = places.map { place in
            Mark(tool: .rectangle, style: MarkStyle(color: .red, size: .thick), points: [place, CGPoint(x: place.x + 40, y: place.y + 30)])
        }
        /// The shortest time of 5 runs, in milliseconds, after one run that loads the font.
        func milliseconds(_ marks: [Mark]) throws -> Double {
            _ = try composeImage(frozen: frozen, selection: selection, marks: marks)
            var best = Duration.seconds(60)
            for _ in 0..<5 {
                let clock = ContinuousClock()
                let start = clock.now
                _ = try composeImage(frozen: frozen, selection: selection, marks: marks)
                best = min(best, clock.now - start)
            }
            let parts = best.components
            return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        }
        let numberTime = try milliseconds(numbers)
        let rectangleTime = try milliseconds(rectangles)
        print("composeImage, 1000 x 600 points at scale 2: 100 numbers \(numberTime) ms, 100 rectangles \(rectangleTime) ms")
        // A generous ceiling, so a busy computer does not make the test fail.
        #expect(numberTime < 200)
    }
}

/// The geometry of a mark for the Select tool (YAZ-2782): the hit test, the move and the size
/// change. Pure functions of the model, with no view. A Text mark measures its text, so the suite
/// runs on the main actor.
@MainActor @Suite struct MarkGeometryTests {
    /// The box of these tests: 100 by 60 points.
    private let box = CGSize(width: 100, height: 60)

    private func mark(_ tool: Tool, _ size: MarkSize, _ points: [CGPoint]) -> Mark {
        Mark(tool: tool, style: MarkStyle(color: .red, size: size), points: points)
    }

    private func text(_ string: String, at origin: CGPoint, _ size: MarkSize = .thick) -> Mark {
        Mark(tool: .text, style: MarkStyle(color: .red, size: size), points: [origin], text: string, wrapWidth: box.width - origin.x)
    }

    private func isNear(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    /// Rows 5 and 6: the tolerance is 6 points around the line, and the inside of a Rectangle and
    /// of an Ellipse is a part of the mark.
    @Test func theHitTestOfEachKindOfMarkWithItsTolerance() {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        #expect(Mark.hitTolerance == 6)

        // Rectangle, Medium: the line is 4 points, so a click 8 points from its middle still hits.
        let rectangle = mark(.rectangle, .medium, [point(20, 20), point(80, 60)])
        #expect(rectangle.part(at: point(20, 40)) == .line)
        #expect(rectangle.part(at: point(12, 40)) == .line && rectangle.part(at: point(11, 40)) == nil)
        #expect(rectangle.part(at: point(12, 12)) == .line && rectangle.part(at: point(11, 12)) == nil)
        #expect(rectangle.part(at: point(50, 68)) == .line && rectangle.part(at: point(50, 69)) == nil)
        #expect(rectangle.part(at: point(28, 40)) == .line && rectangle.part(at: point(29, 40)) == .inside)
        #expect(rectangle.part(at: point(50, 40)) == .inside)
        // With no tolerance, only the line itself hits.
        #expect(rectangle.part(at: point(18, 40), tolerance: 0) == .line)
        #expect(rectangle.part(at: point(17, 40), tolerance: 0) == nil)
        #expect(rectangle.part(at: point(23, 40), tolerance: 0) == .inside)

        // Ellipse, Thin: 7 points from the middle of the line. It is not hit at the corner of its rectangle.
        let ellipse = mark(.ellipse, .thin, [point(80, 60), point(20, 20)])
        #expect(ellipse.part(at: point(20, 40)) == .line)
        #expect(ellipse.part(at: point(13, 40)) == .line && ellipse.part(at: point(12, 40)) == nil)
        #expect(ellipse.part(at: point(50, 67)) == .line && ellipse.part(at: point(50, 68)) == nil)
        #expect(ellipse.part(at: point(26, 40)) == .line && ellipse.part(at: point(28, 40)) == .inside)
        #expect(ellipse.part(at: point(50, 40)) == .inside)
        #expect(ellipse.part(at: point(22, 22)) == nil)

        // Arrow, Thick: 9.5 points from the line, and the head, which is wider than that.
        let arrow = mark(.arrow, .thick, [point(20, 30), point(80, 30)])
        #expect(arrow.part(at: point(50, 30)) == .line)
        #expect(arrow.part(at: point(50, 39)) == .line && arrow.part(at: point(50, 40)) == nil)
        #expect(arrow.part(at: point(11, 30)) == .line && arrow.part(at: point(10, 30)) == nil)
        #expect(arrow.part(at: point(89, 30)) == .line && arrow.part(at: point(90, 30)) == nil)
        // The head is 27 points long and 12 points wide at each side of its base, at x 53.
        #expect(arrow.part(at: point(55, 41)) == .line && arrow.part(at: point(55, 19)) == .line)
        #expect(arrow.part(at: point(75, 41)) == nil)
        // The bounds have the round start of the line, the tip, and the full width of the head.
        #expect(isNear(arrow.bounds.minX, 16.5) && isNear(arrow.bounds.maxX, 83.5))
        #expect(isNear(arrow.bounds.minY, 17.85) && isNear(arrow.bounds.maxY, 42.15))

        // Pen, Thin: 7 points from each part of the line, also around a corner.
        let pen = mark(.pen, .thin, [point(10, 10), point(40, 10), point(40, 40)])
        #expect(pen.part(at: point(25, 17)) == .line && pen.part(at: point(25, 18)) == nil)
        #expect(pen.part(at: point(47, 25)) == .line && pen.part(at: point(48, 25)) == nil)
        #expect(pen.part(at: point(44, 6)) == .line && pen.part(at: point(45, 5)) == nil)
        #expect(pen.part(at: point(25, 30)) == nil)

        // Highlight, Thick: the line is 24 points, so 18 points from its middle.
        let highlight = mark(.highlight, .thick, [point(10, 30), point(90, 30)])
        #expect(highlight.part(at: point(50, 48)) == .line && highlight.part(at: point(50, 49)) == nil)
        #expect(highlight.part(at: point(50, 12)) == .line && highlight.part(at: point(50, 11)) == nil)

        // Text: the area of its lines, and 6 points around it.
        let hello = text("Hello", at: point(10, 5))
        let bounds = hello.bounds
        #expect(bounds.minX == 10 && bounds.minY == 5)
        #expect(bounds.width > 40 && bounds.width < 80 && bounds.height > 24 && bounds.height < 36)
        #expect(hello.part(at: point(bounds.midX, bounds.midY)) == .line)
        #expect(hello.part(at: point(bounds.maxX + 5, bounds.midY)) == .line)
        #expect(hello.part(at: point(bounds.maxX + 7, bounds.midY)) == nil)
        #expect(hello.part(at: point(bounds.midX, bounds.maxY + 5)) == .line)
        #expect(hello.part(at: point(bounds.midX, bounds.maxY + 7)) == nil)
    }

    /// Row 7, and the addition to it: a line wins over the empty inside of a larger mark.
    @Test func theMarkThatWasDrawnLastWinsAndALineWinsOverAnEmptyInside() {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        var list = MarkList()
        #expect(list.index(at: point(50, 30)) == nil)
        list.add(mark(.pen, .thin, [point(10, 30), point(90, 30)])) // 0: a line from the left to the right
        list.add(mark(.pen, .thin, [point(50, 10), point(50, 50)])) // 1: a line from the top to the bottom
        // The two lines cross at 50, 30: the line that was drawn last wins.
        #expect(list.index(at: point(50, 30)) == 1)
        #expect(list.index(at: point(20, 30)) == 0)
        #expect(list.index(at: point(50, 45)) == 1)
        #expect(list.index(at: point(80, 50)) == nil)

        // A large rectangle that was drawn last, around the two lines.
        list.add(mark(.rectangle, .thin, [point(5, 5), point(95, 55)])) // 2
        // In its empty inside, away from the lines: the rectangle.
        #expect(list.index(at: point(75, 45)) == 2)
        // On a line inside it: the line, although the rectangle was drawn last.
        #expect(list.index(at: point(50, 30)) == 1)
        #expect(list.index(at: point(30, 33)) == 0)
        // On the line of the rectangle and on the first line: two lines, so the last one wins.
        #expect(list.index(at: point(8, 30)) == 2)

        // Two rectangles, the small one inside the large one. In both insides, the last one wins.
        var small = MarkList()
        small.add(mark(.rectangle, .thin, [point(30, 20), point(60, 40)]))
        small.add(mark(.rectangle, .thin, [point(5, 5), point(95, 55)]))
        #expect(small.index(at: point(45, 30)) == 1)
        // The line of the small rectangle still selects it.
        #expect(small.index(at: point(30, 30)) == 0)
        var large = MarkList()
        large.add(mark(.rectangle, .thin, [point(5, 5), point(95, 55)]))
        large.add(mark(.rectangle, .thin, [point(30, 20), point(60, 40)]))
        #expect(large.index(at: point(45, 30)) == 1 && large.index(at: point(80, 30)) == 0)
    }

    /// YAZ-2841 rows 1.8, 1.12 and 1.15: the circle of a Number mark is its hit area, it has no
    /// handles, a move stops at the edge, and a new number stays half a circle inside the box.
    @Test func theGeometryOfANumber() {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        // Medium is 30 points: the circle is 15 points around the middle.
        let number = Mark(tool: .number, style: MarkStyle(color: .red, size: .medium), points: [point(50, 30)], number: 1)
        #expect(number.bounds == CGRect(x: 35, y: 15, width: 30, height: 30))
        #expect(number.outline == CGRect(x: 32, y: 12, width: 36, height: 36))

        // A click in the circle, or 6 points around it, selects the number.
        #expect(number.part(at: point(50, 30)) == .line)
        #expect(number.part(at: point(50 + 15 + 6, 30)) == .line && number.part(at: point(50 + 15 + 7, 30)) == nil)
        #expect(number.part(at: point(50, 30 - 15 - 6)) == .line && number.part(at: point(50, 30 - 15 - 7)) == nil)
        // The corner of the bounds is 21.2 points from the middle: not in the hit area.
        #expect(number.part(at: point(35, 15)) == nil)

        // No handles: it only moves. The move stops when the circle touches an edge.
        #expect(number.handles.isEmpty && number.handle(at: point(35, 15)) == nil)
        #expect(number.moved(by: point(10, 5), in: box).points == [point(60, 35)])
        #expect(number.moved(by: point(900, 900), in: box).points == [point(85, 45)])
        #expect(number.moved(by: point(-900, -900), in: box).points == [point(15, 15)])
        #expect(number.moved(by: point(900, 900), in: box).number == 1)

        // A new number keeps its middle half a circle inside the box, so the full circle shows.
        let thick = MarkStyle(color: .red, size: .thick) // 40 points
        #expect(thick.pointInBox(point(0, 0), for: .number, in: box) == point(20, 20))
        #expect(thick.pointInBox(point(500, 500), for: .number, in: box) == point(80, 40))
        #expect(thick.pointInBox(point(50, 30), for: .number, in: box) == point(50, 30))
        #expect(MarkStyle(color: .red, size: .thin).pointInBox(point(0, 70), for: .number, in: box) == point(11, 49))
        // In a box smaller than the circle, the circle is in the middle of the box.
        #expect(thick.pointInBox(point(0, 0), for: .number, in: CGSize(width: 30, height: 20)) == point(15, 10))
        #expect(thick.pointInBox(point(99, 99), for: .number, in: CGSize(width: 30, height: 20)) == point(15, 10))

        // The mark that was drawn last wins, as for each mark. A number on the line of a
        // rectangle that was drawn later: the rectangle. A number inside a rectangle: the number.
        var list = MarkList()
        list.add(number)
        list.add(mark(.rectangle, .thin, [point(40, 20), point(90, 55)]))
        #expect(list.index(at: point(40, 30)) == 1)
        #expect(list.index(at: point(50, 30)) == 0)
        list.add(Mark(tool: .number, style: thick, points: [point(40, 30)], number: 2))
        #expect(list.index(at: point(40, 30)) == 2)
    }

    /// Row 12: the move stops when the bounds of the mark touch an edge of the box.
    @Test func aMoveStopsAtTheEdgesOfTheBox() {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        // Medium is 4 points: the bounds are 2 points around the rectangle of the drag.
        let rectangle = mark(.rectangle, .medium, [point(20, 10), point(60, 40)])
        #expect(rectangle.bounds == CGRect(x: 18, y: 8, width: 44, height: 34))
        #expect(rectangle.outline == CGRect(x: 15, y: 5, width: 50, height: 40))
        #expect(rectangle.moved(by: point(10, 5), in: box).points == [point(30, 15), point(70, 45)])
        // A move uses whole points, so a sharp line stays sharp.
        #expect(rectangle.moved(by: point(10.4, 4.6), in: box).points == [point(30, 15), point(70, 45)])
        #expect(rectangle.moved(by: point(900, 900), in: box).points == [point(58, 28), point(98, 58)])
        #expect(rectangle.moved(by: point(-900, -900), in: box).points == [point(2, 2), point(42, 32)])
        #expect(rectangle.moved(by: point(900, -3), in: box).points == [point(58, 7), point(98, 37)])

        // Each kind of mark: in each direction the bounds stop at the edge, and the shape stays.
        let marks = [
            rectangle,
            mark(.ellipse, .thick, [point(60, 40), point(30, 20)]),
            mark(.arrow, .thick, [point(30, 20), point(60, 40)]),
            mark(.pen, .thick, [point(30, 20), point(45, 35), point(60, 25)]),
            mark(.highlight, .thick, [point(30, 30), point(60, 32)]),
            text("Hi", at: point(30, 15)),
        ]
        for mark in marks {
            let start = mark.bounds
            #expect(start.minX > 0 && start.minY > 0 && start.maxX < box.width && start.maxY < box.height, "\(mark.tool)")
            let far = mark.moved(by: point(900, 900), in: box)
            let near = mark.moved(by: point(-900, -900), in: box)
            if mark.tool == .text {
                // A text stays on whole points, so it stops less than 1 point before the edge.
                #expect(far.bounds.maxX <= 100 && far.bounds.maxX > 99 && far.bounds.maxY <= 60 && far.bounds.maxY > 59)
                // Its lines break at the right edge of the box, and it still has the same lines.
                #expect(far.wrapWidth == box.width - far.points[0].x && near.wrapWidth == 100)
                #expect(far.bounds.size == start.size && near.bounds.size == start.size)
            } else {
                #expect(isNear(far.bounds.maxX, 100) && isNear(far.bounds.maxY, 60), "\(mark.tool)")
            }
            #expect(isNear(near.bounds.minX, 0) && isNear(near.bounds.minY, 0), "\(mark.tool)")
            for moved in [far, near] {
                #expect(isNear(moved.bounds.width, start.width) && isNear(moved.bounds.height, start.height), "\(mark.tool)")
                let shift = CGPoint(x: moved.points[0].x - mark.points[0].x, y: moved.points[0].y - mark.points[0].y)
                #expect(moved.points == mark.points.map { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }, "\(mark.tool)")
                #expect(moved.style == mark.style && moved.text == mark.text)
            }
        }
    }

    /// Rows 10, 13 and 14: the handles, and a size change of a Rectangle, an Ellipse and an Arrow.
    @Test func aSizeChangeOfARectangleAnEllipseAndAnArrow() throws {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        let rectangle = mark(.rectangle, .medium, [point(60, 40), point(20, 10)])

        // Eight handles, on the corners and the edge middles of the rectangle. The hit area is
        // the hit area of a handle of the box: 12 by 12 points.
        #expect(rectangle.handles.map(\.key) == Handle.allCases.map { MarkHandle.frame($0) })
        #expect(rectangle.handles.map(\.point) == [
            point(20, 10), point(60, 10), point(60, 40), point(20, 40),
            point(40, 10), point(60, 25), point(40, 40), point(20, 25),
        ])
        #expect(rectangle.handle(at: point(62, 27))?.key == .frame(.right))
        #expect(rectangle.handle(at: point(66, 25))?.key == .frame(.right) && rectangle.handle(at: point(67, 25)) == nil)
        #expect(rectangle.handle(at: point(58, 43))?.key == .frame(.bottomRight))
        #expect(rectangle.handle(at: point(40, 25)) == nil)

        func frame(_ handle: Handle, to target: CGPoint, of mark: Mark? = nil) -> CGRect {
            (mark ?? rectangle).resized(.frame(handle), to: target, in: box).frame
        }
        // A corner handle changes two edges. An edge handle changes one edge.
        #expect(frame(.bottomRight, to: point(80, 50)) == CGRect(x: 20, y: 10, width: 60, height: 40))
        #expect(frame(.topLeft, to: point(10, 5)) == CGRect(x: 10, y: 5, width: 50, height: 35))
        #expect(frame(.left, to: point(30, 999)) == CGRect(x: 30, y: 10, width: 30, height: 30))
        #expect(frame(.bottom, to: point(-999, 50)) == CGRect(x: 20, y: 10, width: 40, height: 40))
        for handle in Handle.allCases {
            // Each handle moves only its own edges.
            let resized = frame(handle, to: point(50, 30))
            #expect(resized.minX == (handle.horizontal < 0 ? 50 : 20) && resized.minY == (handle.vertical < 0 ? 30 : 10), "\(handle)")
            #expect(resized.maxX == (handle.horizontal > 0 ? 50 : 60) && resized.maxY == (handle.vertical > 0 ? 30 : 40), "\(handle)")
        }
        // The size change stops in the box: the middle of the line is half a line width inside.
        #expect(frame(.bottomRight, to: point(900, 900)) == CGRect(x: 20, y: 10, width: 78, height: 48))
        #expect(frame(.topLeft, to: point(-900, -900)) == CGRect(x: 2, y: 2, width: 58, height: 38))
        // Through the opposite edge the rectangle turns over, and it stays correct.
        #expect(frame(.left, to: point(90, 25)) == CGRect(x: 60, y: 10, width: 30, height: 30))
        #expect(frame(.bottomRight, to: point(5, 4)) == CGRect(x: 5, y: 4, width: 15, height: 6))
        // The smallest side is 4 points.
        #expect(frame(.right, to: point(21, 25)) == CGRect(x: 20, y: 10, width: 4, height: 30))
        #expect(frame(.bottomRight, to: point(20, 10)) == CGRect(x: 20, y: 10, width: 4, height: 4))
        // Whole points, as the box.
        #expect(frame(.bottomRight, to: point(70.4, 44.6)) == CGRect(x: 20, y: 10, width: 50, height: 35))
        // The style and the kind stay.
        let resized = rectangle.resized(.frame(.right), to: point(80, 25), in: box)
        #expect(resized.tool == .rectangle && resized.style == rectangle.style && resized.points.count == 2)

        // A Thick rectangle that was drawn to the edge of the box has edges on half points
        // (3.5 points inside). An edge that does not move stays exactly where it is.
        let thick = mark(.rectangle, .thick, [point(20, 10), point(96.5, 56.5)])
        #expect(frame(.topLeft, to: point(30, 20), of: thick) == CGRect(x: 30, y: 20, width: 66.5, height: 36.5))
        #expect(frame(.left, to: point(-900, 0), of: thick) == CGRect(x: 3.5, y: 10, width: 93, height: 46.5))

        // An Ellipse follows the same rules.
        let ellipse = mark(.ellipse, .thin, [point(20, 10), point(60, 40)])
        #expect(ellipse.handles.count == 8)
        #expect(frame(.top, to: point(0, -50), of: ellipse) == CGRect(x: 20, y: 1, width: 40, height: 39))
        #expect(frame(.bottomRight, to: point(80, 50), of: ellipse) == CGRect(x: 20, y: 10, width: 60, height: 40))

        // An Arrow has one handle at each end. A drag of one end moves that end, and the other end stays.
        let arrow = mark(.arrow, .medium, [point(20, 30), point(80, 30)])
        #expect(arrow.handles.map(\.key) == [.end(0), .end(1)])
        #expect(arrow.handles.map(\.point) == [point(20, 30), point(80, 30)])
        #expect(arrow.handle(at: point(83, 27))?.key == .end(1) && arrow.handle(at: point(50, 30)) == nil)
        #expect(arrow.resized(.end(1), to: point(60, 50), in: box).points == [point(20, 30), point(60, 50)])
        #expect(arrow.resized(.end(0), to: point(-50, 500), in: box).points == [point(2, 58), point(80, 30)])
        // An end that comes onto the other end: the arrow keeps a length of 4 points.
        #expect(arrow.resized(.end(1), to: point(21, 30), in: box).points == [point(20, 30), point(24, 30)])
        #expect(arrow.resized(.end(1), to: point(20, 30), in: box) == arrow)

        // A Pen and a Highlight mark have no handle. They only move. A Text has four (YAZ-3318).
        for mark in [mark(.pen, .thin, [point(10, 10), point(40, 40)]), mark(.highlight, .thin, [point(10, 10), point(40, 40)])] {
            #expect(mark.handles.isEmpty && mark.handle(at: mark.points[0]) == nil, "\(mark.tool)")
        }
    }

    /// YAZ-3318 D3 and D4: a corner of a Text changes its font, and the opposite corner stays.
    /// The lines break at the right edge of the box, and a text that gets too tall moves up.
    @Test func aCornerOfATextChangesItsFontAndTheOppositeCornerStays() throws {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        let box = CGSize(width: 400, height: 300)
        func text(_ string: String, at origin: CGPoint) -> Mark {
            Mark(tool: .text, style: MarkStyle(color: .red, size: .thick), points: [origin], text: string, wrapWidth: box.width - origin.x)
        }
        /// The place of a pointer at `scale` along the diagonal of the outline, from the corner that stays.
        func pointer(_ mark: Mark, _ corner: Handle, _ scale: CGFloat) -> CGPoint {
            let opposite: [Handle: Handle] = [.topLeft: .bottomRight, .topRight: .bottomLeft, .bottomRight: .topLeft, .bottomLeft: .topRight]
            let fixed = Selection.handlePoint(opposite[corner]!, of: mark.outline)
            let start = Selection.handlePoint(corner, of: mark.outline)
            return point(fixed.x + (start.x - fixed.x) * scale, fixed.y + (start.y - fixed.y) * scale)
        }

        // Four handles, at the corners of the outline (S11).
        let hi = text("Hi", at: point(100, 100))
        #expect(hi.handles.map(\.key) == [.frame(.topLeft), .frame(.topRight), .frame(.bottomRight), .frame(.bottomLeft)])
        #expect(hi.handles.map(\.point) == [Handle.topLeft, .topRight, .bottomRight, .bottomLeft].map { Selection.handlePoint($0, of: hi.outline) })
        #expect(hi.handle(at: Selection.handlePoint(.bottomRight, of: hi.outline))?.key == .frame(.bottomRight))
        // A pointer that did not move changes nothing.
        #expect(hi.resized(.frame(.bottomRight), to: pointer(hi, .bottomRight, 1), in: box) == hi)

        // The bottom-right corner, two times as far: 48 points, and the top-left stays (S13).
        let larger = hi.resized(.frame(.bottomRight), to: pointer(hi, .bottomRight, 2), in: box)
        #expect(larger.style.fontSize == 48 && larger.points == hi.points && larger.style.color == .red)
        #expect(larger.wrapWidth == box.width - larger.points[0].x)
        // A left or a top corner: the opposite corner stays, to less than a point, and the text
        // stays on whole points (S14). A longer text shows a drift that a short text hides.
        // A larger box, so the text does not reach an edge.
        let wide = CGSize(width: 800, height: 600)
        let words = Mark(
            tool: .text, style: MarkStyle(color: .red, size: .thick), points: [point(300, 250)], text: "Hello world", wrapWidth: 500
        )
        for (corner, scale) in [(Handle.topLeft, CGFloat(3)), (.topLeft, 0.5), (.bottomLeft, 3), (.topRight, 0.5)] {
            let scaled = words.resized(.frame(corner), to: pointer(words, corner, scale), in: wide)
            #expect(scaled.style.fontSize == (24 * scale).rounded(), "\(corner) \(scale)")
            let origin = scaled.points[0]
            #expect(origin.x == origin.x.rounded() && origin.y == origin.y.rounded(), "\(corner) \(scale)")
            if corner.horizontal < 0 {
                #expect(scaled.bounds.maxX <= words.bounds.maxX && scaled.bounds.maxX > words.bounds.maxX - 1, "\(corner) \(scale)")
            } else {
                #expect(scaled.bounds.minX == words.bounds.minX, "\(corner) \(scale)")
            }
            if corner.vertical < 0 {
                #expect(scaled.bounds.maxY <= words.bounds.maxY && scaled.bounds.maxY > words.bounds.maxY - 1, "\(corner) \(scale)")
            } else {
                #expect(scaled.bounds.minY == words.bounds.minY, "\(corner) \(scale)")
            }
        }
        // Half as far: 12 points (S15). Past the opposite corner, and very far: 8 and 256 (S16, S17).
        #expect(hi.resized(.frame(.topRight), to: pointer(hi, .topRight, 0.5), in: box).style.fontSize == 12)
        #expect(hi.resized(.frame(.bottomLeft), to: pointer(hi, .bottomLeft, -3), in: box).style.fontSize == 8)
        #expect(hi.resized(.frame(.bottomRight), to: pointer(hi, .bottomRight, 40), in: box).style.fontSize == 256)

        // Near the right edge, the lines break at the edge (S18). The text stays in the box.
        let edge = text("Look here", at: point(300, 20))
        let broken = edge.resized(.frame(.bottomRight), to: pointer(edge, .bottomRight, 2), in: box)
        #expect(broken.style.fontSize == 48 && broken.points == edge.points)
        #expect(broken.bounds.maxX <= box.width && broken.bounds.height > 2 * edge.bounds.height)
        // Near the bottom edge, the text moves up (S19).
        let low = text("Hi", at: point(100, 260))
        let up = low.resized(.frame(.bottomRight), to: pointer(low, .bottomRight, 3), in: box)
        #expect(up.style.fontSize == 72 && up.points[0].x == 100 && up.points[0].y < 260 && up.bounds.maxY <= box.height)
    }

    /// YAZ-3338 (the checker of PR 12): a top-left or bottom-left corner drag that brings a text to
    /// the left edge of the box. Up to the edge, the corner that stays does not move. At the edge,
    /// the text stops at x 0 and grows to the right (D4). It never jumps.
    @Test func aLeftCornerDragToTheLeftEdgeStopsAtTheEdgeAndDoesNotJump() {
        let box = CGSize(width: 400, height: 300)
        let words = Mark(
            tool: .text, style: MarkStyle(color: .red, size: .thick), points: [CGPoint(x: 60, y: 200)],
            text: "Hello world", wrapWidth: 340
        )
        let outline = words.outline
        var lastFont: CGFloat = 0
        for scale in [CGFloat(1.2), 1.45, 1.5, 1.55, 1.6, 2] {
            let pointer = CGPoint(x: outline.maxX - outline.width * scale, y: outline.maxY - outline.height * scale)
            let scaled = words.resized(.frame(.topLeft), to: pointer, in: box)
            // The bottom stays, at each scale.
            #expect(abs(scaled.bounds.maxY - words.bounds.maxY) < 1, "\(scale)")
            #expect(scaled.style.fontSize > lastFont, "\(scale)")
            lastFont = scaled.style.fontSize
            if scaled.points[0].x > 0 {
                // Room on the left: the right edge stays too.
                #expect(scaled.bounds.maxX <= words.bounds.maxX && scaled.bounds.maxX > words.bounds.maxX - 1, "\(scale)")
            } else {
                // At the left edge: the text grows to the right, on one line, in the box.
                #expect(scaled.bounds.maxX >= words.bounds.maxX && scaled.bounds.maxX <= box.width, "\(scale)")
            }
            let bottomLeft = words.resized(.frame(.bottomLeft), to: CGPoint(x: pointer.x, y: outline.minY + outline.height * scale), in: box)
            #expect(bottomLeft.bounds.minY == words.bounds.minY && bottomLeft.points[0].x >= 0, "\(scale)")
        }
        // The last scales reach the left edge.
        #expect(words.resized(.frame(.topLeft), to: CGPoint(x: -100, y: 0), in: box).points[0].x == 0)

        // A top corner drag past the top edge: the text stops at y 0 and grows down. It never jumps.
        let high = Mark(
            tool: .text, style: MarkStyle(color: .red, size: .thick), points: [CGPoint(x: 100, y: 20)],
            text: "Hi", wrapWidth: 300
        )
        let highOutline = high.outline
        var lastBottom = high.bounds.maxY
        for scale in [CGFloat(1.2), 1.5, 2, 3] {
            // Along the diagonal, from the bottom-left corner that stays.
            let pointer = CGPoint(
                x: highOutline.minX + highOutline.width * scale, y: highOutline.maxY - highOutline.height * scale
            )
            let scaled = high.resized(.frame(.topRight), to: pointer, in: box)
            #expect(scaled.points[0].y >= 0 && scaled.bounds.minX == high.bounds.minX, "\(scale)")
            if scaled.points[0].y > 0 {
                #expect(abs(scaled.bounds.maxY - high.bounds.maxY) < 1, "\(scale)")
            } else {
                #expect(scaled.bounds.maxY >= lastBottom, "\(scale)")
            }
            lastBottom = scaled.bounds.maxY
        }
    }

    /// YAZ-3318 D1: a size sets the font of a Text again, also after a free font.
    @Test func aSizeSetsTheFontAgainAfterAFreeFont() {
        var style = MarkStyle(color: .red, size: .thin)
        #expect(style.fontSize == 14)
        style.fontSize = 72
        #expect(style != MarkStyle(color: .red, size: .thin))
        style.size = .medium
        #expect(style == MarkStyle(color: .red, size: .medium) && style.fontSize == 18)
    }
}

/// The clipboard of marks (YAZ-3148): a copy, a cut, and where each paste goes. The rows are the
/// scenarios on the working log YAZ-3150.
@Suite struct MarkClipboardTests {
    let box = CGSize(width: 200, height: 100)
    /// A Thick rectangle (a line of 7 points): x 10 to 30, y 10 to 20 of the box.
    let rectangle = Mark(
        tool: .rectangle, style: MarkStyle(color: .red, size: .thick), points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 20)]
    )

    @Test func eachPasteAfterACopyIs16PointsFurtherAndTheFirstPasteAfterACutIsAtTheSamePlace() {
        let clipboard = MarkClipboard()
        #expect(clipboard.nextPaste(in: box) == nil) // nothing was copied (row 16)

        clipboard.copy(rectangle)
        let pastes = (0..<3).compactMap { _ in clipboard.nextPaste(in: box) }
        #expect(pastes.map(\.frame.origin) == [CGPoint(x: 26, y: 26), CGPoint(x: 42, y: 42), CGPoint(x: 58, y: 58)]) // rows 10, 11
        #expect(pastes.allSatisfy { $0.frame.size == rectangle.frame.size && $0.style == rectangle.style })

        clipboard.cut(rectangle)
        #expect(clipboard.nextPaste(in: box) == rectangle) // row 12
        #expect(clipboard.nextPaste(in: box)?.frame.origin == CGPoint(x: 26, y: 26))
    }

    @Test func aPasteStaysInTheBoxAndANumberKeepsItsNumber() throws {
        let clipboard = MarkClipboard()
        // Near the bottom-right corner, the paste stops at the edges, and the next paste stacks on it (row 13).
        clipboard.copy(Mark(tool: .rectangle, style: rectangle.style, points: [CGPoint(x: 170, y: 80), CGPoint(x: 190, y: 90)]))
        let atTheEdge = try #require(clipboard.nextPaste(in: box))
        #expect(atTheEdge.bounds.maxX == 200 && atTheEdge.bounds.maxY == 100)
        #expect(clipboard.nextPaste(in: box) == atTheEdge)

        // A smaller box, as in the next capture (row 23): the copy moves in. A mark that is larger
        // than the box keeps its top-left corner in the box.
        clipboard.copy(Mark(tool: .rectangle, style: rectangle.style, points: [CGPoint(x: 150, y: 70), CGPoint(x: 190, y: 90)]))
        let small = CGSize(width: 60, height: 40)
        #expect(clipboard.nextPaste(in: small).map { CGRect(origin: .zero, size: small).contains($0.bounds) } == true)
        clipboard.copy(Mark(tool: .rectangle, style: rectangle.style, points: [CGPoint(x: 100, y: 40), CGPoint(x: 190, y: 90)]))
        #expect(clipboard.nextPaste(in: small)?.bounds.origin == .zero)

        // A copy of number 3 is number 3 (D4, row 25).
        clipboard.copy(Mark(tool: .number, style: .initial(for: .number), points: [CGPoint(x: 50, y: 50)], number: 3))
        #expect(clipboard.nextPaste(in: box)?.number == 3)
    }

    /// A Text mark keeps its text and its style. In a smaller box, its lines break at the right
    /// edge of that box (row 26, row 23). A Text mark measures its text, so the test runs on the main actor.
    @MainActor @Test func aTextKeepsItsTextAndBreaksAtTheRightEdgeOfTheNewBox() {
        let clipboard = MarkClipboard()
        let text = Mark(
            tool: .text, style: MarkStyle(color: .blue, size: .medium), points: [CGPoint(x: 10, y: 10)], text: "tabs", wrapWidth: 190
        )
        clipboard.copy(text)
        let pasted = clipboard.nextPaste(in: CGSize(width: 120, height: 80))
        #expect(pasted?.text == "tabs" && pasted?.style == text.style)
        #expect(pasted?.points == [CGPoint(x: 26, y: 26)] && pasted?.wrapWidth == 120 - 26)
    }
}
