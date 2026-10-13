import AppKit

/// The borderless window that covers one screen during a capture (D5).
final class OverlayWindow: NSWindow {
    let overlayView: OverlayView

    init(display: FrozenDisplay, interaction: CaptureInteraction) {
        overlayView = OverlayView(display: display, interaction: interaction)
        super.init(contentRect: display.frame, styleMask: .borderless, backing: .buffered, defer: false)

        // Above a full-screen app, the menu bar and the Dock, on every Space.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = overlayView
        // Each window sends its keys to its view, also the window that gets the keyboard after a click.
        initialFirstResponder = overlayView
        makeFirstResponder(overlayView)
        setFrame(display.frame, display: false)
    }

    // A borderless window refuses the keyboard by default. The overlay needs Enter and Esc.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
