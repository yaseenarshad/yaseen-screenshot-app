import AppKit

/// One capture on the screens: one `OverlayWindow` for each `FrozenDisplay`.
///
/// It ends one time, with a result or with a cancel. It closes all windows in the two cases.
@MainActor
final class CaptureSession {
    private let interaction: CaptureInteraction
    private let onEnd: (CaptureOutcome) -> Void
    private var windows: [OverlayWindow] = []
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?

    init(displays: [FrozenDisplay], onEnd: @escaping (CaptureOutcome) -> Void) {
        self.interaction = CaptureInteraction(displays: displays)
        self.onEnd = onEnd
    }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isThisApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        previousApp = isThisApp ? nil : frontmost

        windows = interaction.displays.map { OverlayWindow(display: $0, interaction: interaction) }
        interaction.onChange = { [weak self] in
            self?.windows.forEach { $0.overlayView.refresh() }
        }
        interaction.onFinish = { [weak self] outcome in
            self?.end(outcome)
        }

        let center = NotificationCenter.default
        // A display was added or removed: the frozen images no longer fit the screens.
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.interaction.cancel() }
        })
        // The user went to a different app (for example with Command-Tab). That app stays active.
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.previousApp = nil
                self?.interaction.cancel()
            }
        })

        // The window below the pointer gets the keyboard. The app must be active to receive Enter and Esc.
        let pointer = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(pointer) } ?? windows.first
        windows.forEach { $0.orderFrontRegardless() }
        keyWindow?.makeKey()
        NSApp.activate()
        NSCursor.crosshair.set()
    }

    private func end(_ outcome: CaptureOutcome) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        // AppKit can still be inside an event of one of these windows. Thus the windows, and the
        // frozen images that they show, go away on the next turn of the run loop.
        let closed = windows
        windows = []
        closed.forEach { $0.orderOut(nil) }
        DispatchQueue.main.async { withExtendedLifetime(closed) {} }
        NSCursor.arrow.set()

        if let previousApp = previousApp {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        onEnd(outcome)
    }
}
