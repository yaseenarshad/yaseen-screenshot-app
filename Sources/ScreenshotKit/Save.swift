import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum SaveError: LocalizedError {
    case encodeFailed
    case noFreeFileName

    public var errorDescription: String? {
        switch self {
        case .encodeFailed: return "The image could not be made into a PNG."
        case .noFreeFileName: return "The folder has no free file name."
        }
    }
}

/// Copies the image to a pasteboard and writes it to a folder.
///
/// The pasteboard and the folder are parameters, so a test uses its own pasteboard and a temporary folder.
public final class ScreenshotSaver {
    /// The file was not written. The image is on the pasteboard already.
    /// The failure keeps the PNG, so the app can write it to a different folder.
    public struct FileFailure: Error {
        public let folder: URL
        public let png: Data
        public let date: Date
        public let underlying: Error
    }

    public typealias FileCompletion = (Result<URL, FileFailure>) -> Void

    public var folder: URL
    private let pasteboard: NSPasteboard
    private let writeQueue = DispatchQueue(label: "com.yaseenarshad.yaseenscreenshot.save", qos: .userInitiated)
    private let pendingWrites = DispatchGroup()

    public init(pasteboard: NSPasteboard, folder: URL) {
        self.pasteboard = pasteboard
        self.folder = folder
    }

    /// The end of a capture, with no window: nothing for a cancel; the image, the copy and the file for a done.
    public func deliver(
        _ outcome: CaptureOutcome,
        date: Date = Date(),
        fileCompletion: @escaping FileCompletion = { _ in }
    ) throws {
        guard case .done(let result) = outcome else { return }
        let image = try composeFinalImage(frozen: result.display, selection: result.selection, marks: result.marks)
        try save(image, scale: result.display.scale, date: date, fileCompletion: fileCompletion)
    }

    /// Copies the image now, and writes the file in the background.
    /// `fileCompletion` runs on the main queue.
    public func save(
        _ image: CGImage,
        scale: CGFloat,
        date: Date = Date(),
        fileCompletion: @escaping FileCompletion = { _ in }
    ) throws {
        let png = try ScreenshotSaver.encode(image, as: .png, scale: scale)
        // Old apps read only TIFF from the pasteboard.
        let tiff = try ScreenshotSaver.encode(image, as: .tiff, scale: scale)

        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        writeFile(png, date: date, completion: fileCompletion)
    }

    /// Writes the PNG to the folder in the background. `completion` runs on the main queue.
    public func writeFile(_ png: Data, date: Date, completion: @escaping FileCompletion = { _ in }) {
        let folder = self.folder
        pendingWrites.enter()
        writeQueue.async {
            let result: Result<URL, FileFailure>
            do {
                result = .success(try ScreenshotSaver.writeWithoutOverwrite(png, in: folder, date: date))
            } catch {
                result = .failure(FileFailure(folder: folder, png: png, date: date, underlying: error))
            }
            self.pendingWrites.leave()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Blocks until every file write that started is complete. The app calls this before it quits.
    public func waitForPendingWrites() {
        pendingWrites.wait()
    }

    // MARK: The PNG and the file

    private static func encode(_ image: CGImage, as type: UTType, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw SaveError.encodeFailed
        }
        // 72 dpi multiplied by the scale: an app then shows the image at its size in points.
        let dpi = 72 * scale
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if type == .tiff {
            // LZW (5): without it, the TIFF of a full Retina screen is about 30 MB.
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SaveError.encodeFailed }
        return data as Data
    }

    /// Atomic, and it never writes over a file: a temporary file in the same folder,
    /// then a move to the final name that fails when the name exists.
    private static func writeWithoutOverwrite(_ png: Data, in folder: URL, date: Date) throws -> URL {
        let temporary = folder.appendingPathComponent(".Snip-\(UUID().uuidString).tmp")
        try png.write(to: temporary)
        do {
            // A different app can take the name between the read of the folder and the move
            // (Snip, in the same second). Then read the folder again and use the next number.
            for _ in 0..<20 {
                let target = try nextSnipFileURL(in: folder, date: date)
                if try moveWithoutOverwrite(temporary, to: target) { return target }
            }
            throw SaveError.noFreeFileName
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Returns `false` when `target` exists. Not private: a test proves that it keeps the file that exists.
    static func moveWithoutOverwrite(_ source: URL, to target: URL) throws -> Bool {
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 { return true }
        switch errno {
        case EEXIST:
            return false
        case ENOTSUP:
            // The volume has no exclusive rename (for example exFAT). `FileManager` also refuses
            // to write over a file, but it checks and moves in two steps.
            do {
                try FileManager.default.moveItem(at: source, to: target)
                return true
            } catch CocoaError.fileWriteFileExists {
                return false
            }
        default:
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
