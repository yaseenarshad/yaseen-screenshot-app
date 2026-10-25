import AppKit

/// The Screen Recording permission of macOS.
enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func openSystemSettings() {
        // This call puts the app in the Screen Recording list, so the user can switch it on.
        // macOS shows its own question the first time only.
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quits the app and opens it again. macOS tells an app about the permission only when it
    /// starts: `CGPreflightScreenCaptureAccess` keeps its first answer. Returns `false` when the
    /// app cannot open itself again; then it does not quit.
    static func relaunch() -> Bool {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The new app starts after this one is gone, so it can take the hotkey.
        shell.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"", "sh",
            String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
        ]
        do {
            try shell.run()
        } catch {
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}

/// The small window that asks for the permission.
@MainActor
final class PermissionWindowController: NSWindowController {
    private let status = NSTextField(labelWithString: "")
    private let isGranted: () -> Bool
    private let relaunch: () -> Bool

    /// The tests give their own `isGranted` and `relaunch`, so a click quits nothing.
    init(
        isGranted: @escaping () -> Bool = { ScreenRecordingPermission.isGranted },
        relaunch: @escaping () -> Bool = ScreenRecordingPermission.relaunch
    ) {
        self.isGranted = isGranted
        self.relaunch = relaunch
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 10),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Yaseen Screenshot"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let text = NSTextField(wrappingLabelWithString:
            "Yaseen Screenshot needs the Screen Recording permission to capture the screen. "
            + "Turn on \"Yaseen Screenshot\" in System Settings, then click Quit and Reopen. "
            + "macOS gives the app the permission only when the app starts again."
        )
        status.textColor = .secondaryLabelColor

        let openSettings = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        let reopen = NSButton(title: "Quit and Reopen", target: self, action: #selector(quitAndReopen))
        openSettings.keyEquivalent = "\r"
        // The empty view takes the free width, so the buttons stay on the right.
        let buttons = NSStackView(views: [NSView(), reopen, openSettings])
        buttons.orientation = .horizontal
        buttons.distribution = .fill

        // The status line is empty until the app cannot open itself again.
        let stack = NSStackView(views: [text, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        NSLayoutConstraint.activate([
            text.widthAnchor.constraint(equalToConstant: 400),
            buttons.widthAnchor.constraint(equalTo: text.widthAnchor),
        ])
        window.contentView = stack
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show() {
        status.stringValue = ""
        // macOS can refuse `NSApp.activate()` when a different app is active. `orderFrontRegardless`
        // puts the window in front also then (the same rule as the settings window).
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    @objc private func openSettings() {
        ScreenRecordingPermission.openSystemSettings()
    }

    /// The permission that the user gave now shows only after a new start (YAZ-3318). If the app
    /// already has it, there is nothing to start again.
    @objc private func quitAndReopen() {
        if isGranted() {
            close()
        } else if !relaunch() {
            status.stringValue = "The app could not open again. Quit it from the menu bar, and open it again."
        }
    }
}
