import Foundation
import ScreenshotKit
import Testing

@Suite struct FileNameTests {
    let day = localDate(year: 2026, month: 10, day: 12)

    @Test func nameForADateAndANumber() {
        #expect(snipFileName(date: day, number: 16) == "Snip20261012_16.png")
        #expect(snipFileName(date: localDate(year: 2027, month: 1, day: 5), number: 1) == "Snip20270105_1.png")
    }

    @Test func nextNumberIsOneMoreThanTheHighestOfThatDate() {
        #expect(nextSnipNumber(after: [], date: day) == 1)

        let names = [
            "Snip20261012_3.png", "Snip20261012_15.png", "Snip20261012_9.png",
            // Other dates do not count.
            "Snip20261011_99.png", "Snip20251012_400.png",
            // Other files do not count.
            "Snip20261012_.png", "Snip20261012_abc.png", "Snip20261012_+30.png", "Snip20261012_-31.png",
            "Snip20261012_32.jpg", "Snip20261012_33.png.bak", "XSnip20261012_34.png", "Snip20261012_3 5.png",
            "Screenshot 2026-10-12.png", ".Snip-1234.tmp",
        ]
        #expect(nextSnipNumber(after: names, date: day) == 16)

        // The usual Mac volume does not see the case of a name. A name in a different case is taken.
        #expect(nextSnipNumber(after: names + ["snip20261012_20.PNG"], date: day) == 21)
    }

    @Test func nextFileURLReadsTheFolder() throws {
        let sandbox = try Sandbox()
        #expect(try nextSnipFileURL(in: sandbox.folder, date: day).lastPathComponent == "Snip20261012_1.png")

        for name in ["Snip20261012_4.png", "Snip20261011_8.png", "notes.txt"] {
            try Data().write(to: sandbox.folder.appendingPathComponent(name))
        }
        let next = try nextSnipFileURL(in: sandbox.folder, date: day)
        #expect(next.lastPathComponent == "Snip20261012_5.png")
        #expect(next.deletingLastPathComponent().standardizedFileURL == sandbox.folder.standardizedFileURL)

        let missing = sandbox.folder.appendingPathComponent("missing")
        #expect(throws: (any Error).self) { try nextSnipFileURL(in: missing, date: day) }
    }

    /// Yaseen's `~/Pictures` has about 5,650 files from Snip. The read of the names must not slow a capture.
    @Test func sixThousandNamesTakeLessThan50Milliseconds() {
        var names: [String] = []
        for dayOfMonth in 1...30 {
            let date = localDate(year: 2026, month: 9, day: dayOfMonth)
            names += (1...190).map { snipFileName(date: date, number: $0) }
        }
        names += (1...300).map { snipFileName(date: day, number: $0) }
        #expect(names.count == 6_000)

        // The other tests run at the same time and can take the processor for a moment.
        // Thus the test uses the best of three measurements.
        var next = 0
        let elapsed = (1...3).map { _ in
            ContinuousClock().measure { next = nextSnipNumber(after: names, date: day) }
        }.min()!
        #expect(next == 301)
        #expect(elapsed < .milliseconds(50), "6,000 names took \(elapsed)")
        print("FileNameTests: 6,000 names took \(elapsed)")
    }
}
