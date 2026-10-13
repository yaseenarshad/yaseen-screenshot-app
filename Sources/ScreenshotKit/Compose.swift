import CoreGraphics
import Foundation

public enum ComposeError: LocalizedError {
    case noBitmap

    public var errorDescription: String? {
        "The image with the marks could not be made."
    }
}

/// Makes the image that the user gets: the frozen image, cropped to the box in pixels, with the marks.
public func composeFinalImage(frozen: FrozenDisplay, selection: Selection, marks: MarkList) throws -> CGImage {
    try composeImage(frozen: frozen, selection: selection, marks: marks.marks)
}

/// The same image for a plain list of marks. The overlay shows this image in the box while the
/// user draws, so the overlay and the saved file have the same pixels.
func composeImage(frozen: FrozenDisplay, selection: Selection, marks: [Mark]) throws -> CGImage {
    let imageBounds = CGRect(x: 0, y: 0, width: frozen.image.width, height: frozen.image.height)
    let pixelRect = selection.pixelRect(scale: frozen.scale).intersection(imageBounds)
    guard !pixelRect.isEmpty, let crop = frozen.image.cropping(to: pixelRect) else {
        throw CaptureError.cropFailed
    }
    guard !marks.isEmpty else { return crop }

    // The marks are drawn in the colour space of the screen image, so the pixels with no mark stay the same.
    let imageSpace = crop.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
    guard let space = imageSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: crop.width,
              height: crop.height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { throw ComposeError.noBitmap }

    context.interpolationQuality = .none
    context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))

    // The marks are in the points of the box, from its top-left. A bitmap starts at the bottom-left,
    // in pixels. A line of 4 points is 8 pixels wide at scale 2.
    context.translateBy(x: 0, y: CGFloat(crop.height))
    context.scaleBy(x: frozen.scale, y: -frozen.scale)
    MarkRenderer.draw(marks, in: context)

    guard let image = context.makeImage() else { throw ComposeError.noBitmap }
    return image
}
