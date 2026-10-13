import Foundation

// The file names continue the pattern of Snip: "Snip20261012_16.png".
// The date is the local day. The number is 1 more than the highest number of that day in the folder.

public func snipFileName(date: Date, number: Int) -> String {
    "\(snipPrefix(for: date))\(number).png"
}

/// The number for the next file of the day of `date`, from the names that a folder has now.
/// Other days and other files do not count.
public func nextSnipNumber(after names: [String], date: Date) -> Int {
    // Lowercase on the two sides: the usual Mac volume sees "snip…_3.PNG" and "Snip…_3.png" as one file.
    let prefix = snipPrefix(for: date).lowercased()
    let suffix = ".png"
    var highest = 0
    for name in names {
        let lowered = name.lowercased()
        guard lowered.hasPrefix(prefix), lowered.hasSuffix(suffix) else { continue }
        let digits = lowered.dropFirst(prefix.count).dropLast(suffix.count)
        guard !digits.isEmpty,
              digits.allSatisfy({ ("0"..."9").contains($0) }),
              let number = Int(digits)
        else { continue }
        highest = max(highest, number)
    }
    return highest + 1
}

/// The URL for the next file in `folder`. It throws when the folder cannot be read.
public func nextSnipFileURL(in folder: URL, date: Date) throws -> URL {
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    let number = nextSnipNumber(after: names, date: date)
    return folder.appendingPathComponent(snipFileName(date: date, number: number))
}

private func snipPrefix(for date: Date) -> String {
    // A fixed Gregorian calendar: the name must not change with the calendar setting of the user.
    let day = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    return String(format: "Snip%04d%02d%02d_", day.year ?? 0, day.month ?? 0, day.day ?? 0)
}
