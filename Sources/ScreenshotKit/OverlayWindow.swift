import AppKit

/// The borderless panel that covers one screen during a capture (D5).
///
/// It is a panel that does not activate the app. Such a panel takes the keyboard also when macOS
/// refuses to make this app the active app. Then Enter, Esc and the typing of a text still arrive.
final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    init(display: FrozenDisplay, interaction: CaptureInteraction) {
        overlayView = OverlayView(display: display, interaction: interaction)
        super.init(
            contentRect: display.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Above a full-screen app, the menu bar and the Dock, on every Space.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // A panel takes the keyboard only for a text field, and hides when its app is not active.
        // The overlay needs the keyboard at once, and it must stay.
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isFloatingPanel = false
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
        // `isFloatingPanel` changes the level, so the level is set again after it.
        level = .screenSaver
        setFrame(display.frame, display: false)
    }

    // A borderless window refuses the keyboard by default. The overlay needs Enter and Esc.
    override var canBecomeKey: Bool { true }
}
