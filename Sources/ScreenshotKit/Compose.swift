import CoreGraphics

/// Makes the image that the user gets: the frozen image, cropped to the box in pixels.
/// Subissue 3 (YAZ-2767) also draws the marks here.
public func composeFinalImage(frozen: FrozenDisplay, selection: Selection, marks: MarkList) throws -> CGImage {
    let imageBounds = CGRect(x: 0, y: 0, width: frozen.image.width, height: frozen.image.height)
    let pixelRect = selection.pixelRect(scale: frozen.scale).intersection(imageBounds)
    guard !pixelRect.isEmpty, let image = frozen.image.cropping(to: pixelRect) else {
        throw CaptureError.cropFailed
    }
    return image
}
