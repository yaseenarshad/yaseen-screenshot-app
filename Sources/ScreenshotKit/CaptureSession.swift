import AppKit

/// One capture on the screens: one `OverlayWindow` for each `FrozenDisplay`.
///
/// It ends one time, with a result or with a cancel. It closes all windows in the two cases.
@MainActor
final class CaptureSession {
    private let interaction: CaptureInteraction
    private let onEnd: (CaptureOutcome) -> Void
    private var windows: [OverlayWindow] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var previousApp: NSRunningApplication?

    init(displays: [FrozenDisplay], onEnd: @escaping (CaptureOutcome) -> Void) {
        self.interaction = CaptureInteraction(displays: displays)
        self.onEnd = onEnd
    }

    func show() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ownPID ? nil : frontmost

        windows = interaction.displays.map { OverlayWindow(display: $0, interaction: interaction) }
        interaction.onChange = { [weak self] in
            self?.windows.forEach { $0.overlayView.refresh() }
        }
        interaction.onFinish = { [weak self] outcome in
            self?.end(outcome)
        }

        // A display was added or removed: the frozen images no longer fit the screens.
        observe(NSApplication.didChangeScreenParametersNotification, in: .default) { [weak self] _ in
            self?.interaction.cancel()
        }
        // The user went to a different app (for example with Command-Tab). That app stays active.
        observe(NSApplication.didResignActiveNotification, in: .default) { [weak self] _ in
            self?.cancelForOtherApp()
        }
        // The panels take the keyboard with no app switch, so this app is not always the active
        // app. Then it never resigns. The workspace still tells when a different app becomes active.
        observe(NSWorkspace.didActivateApplicationNotification, in: NSWorkspace.shared.notificationCenter) {
            [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let app = app, app.processIdentifier != ownPID else { return }
            self?.cancelForOtherApp()
        }

        // The window below the pointer gets the keyboard. The panel can have it when this app is
        // not the active app. The app still asks to be active: then the pointer shapes are sure to show.
        let pointer = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(pointer) } ?? windows.first
        windows.forEach { $0.orderFrontRegardless() }
        keyWindow?.makeKey()
        NSApp.activate()
        NSCursor.crosshair.set()

        // The window list is read one time, on the next turn of the run loop. Thus the frozen
        // screens show first: the first read in the life of the app can take 100 ms.
        DispatchQueue.main.async { [weak self] in
            self?.readWindows()
        }
    }

    /// Reads the windows that a click can select, and makes the window below the pointer bright.
    private func readWindows() {
        guard !windows.isEmpty else { return } // the capture ended already
        interaction.setWindows(WindowSnap.framesByDisplay(
            windows: SystemWindowList.windowsOnScreen(),
            displays: interaction.displays,
            excludingPID: ProcessInfo.processInfo.processIdentifier
        ))
        // The pointer did not move yet, so no view told where it is.
        let pointer = NSEvent.mouseLocation
        if let display = interaction.displays.first(where: { $0.frame.contains(pointer) }) {
            let point = CGPoint(x: pointer.x - display.frame.minX, y: display.frame.maxY - pointer.y)
            interaction.pointerMoved(to: point, on: display.displayID)
        }
    }

    private func observe(
        _ name: Notification.Name,
        in center: NotificationCenter,
        handler: @escaping @MainActor (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        }
        observers.append((center, token))
    }

    private func cancelForOtherApp() {
        previousApp = nil
        interaction.cancel()
    }

    private func end(_ outcome: CaptureOutcome) {
        observers.forEach { $0.center.removeObserver($0.token) }
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
