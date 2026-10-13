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
}

/// The small window that asks for the permission.
@MainActor
final class PermissionWindowController: NSWindowController {
    private let status = NSTextField(labelWithString: "")

    init() {
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
            + "After you give the permission, macOS can ask you to quit and open the app again."
        )
        status.textColor = .secondaryLabelColor

        let openSettings = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        let tryAgain = NSButton(title: "Try again", target: self, action: #selector(tryAgain))
        openSettings.keyEquivalent = "\r"
        // The empty view takes the free width, so the buttons stay on the right.
        let buttons = NSStackView(views: [NSView(), tryAgain, openSettings])
        buttons.orientation = .horizontal
        buttons.distribution = .fill

        // The status line is empty until "Try again" finds that the permission is still off.
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

    @objc private func tryAgain() {
        if ScreenRecordingPermission.isGranted {
            close()
        } else {
            status.stringValue = "The permission is still off."
        }
    }
}
