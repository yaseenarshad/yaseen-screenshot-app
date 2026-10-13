import AppKit
import os

/// The app: it owns the menu, the hotkey and one `CaptureSession` at most.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    public static let bundleIdentifier = "com.yaseenarshad.yaseenscreenshot"

    /// The time between a click on "Take screenshot" and the capture. The menu must be gone from the image.
    private static let menuCloseDelay: TimeInterval = 0.2

    /// What "Settings…" does. The default opens the settings window.
    public lazy var openSettings: () -> Void = { [weak self] in self?.showSettingsWindow() }

    private let capturer: ScreenCapturing
    private let saver: ScreenshotSaver
    private let hotKeyCenter = HotKeyCenter()
    private let settings: SettingsModel
    private let log = Logger(subsystem: AppController.bundleIdentifier, category: "capture")

    private var statusMenu: StatusMenu?
    private var permissionWindow: PermissionWindowController?
    private var settingsWindow: SettingsWindowController?
    private var session: CaptureSession?
    /// True from the trigger until the capture ends. The capture itself is async, so `session` is not enough.
    private var isCapturing = false

    public init(
        capturer: ScreenCapturing = SystemScreenCapture(),
        saver: ScreenshotSaver,
        store: SettingsStore,
        loginItem: LoginItem = SystemLoginItem()
    ) {
        self.capturer = capturer
        self.saver = saver
        settings = SettingsModel(store: store, hotKeys: hotKeyCenter, loginItem: loginItem)
        // The stored folder wins over the folder that the saver came with.
        saver.folder = store.saveFolder
    }

    /// Starts the app with the real screen, the real clipboard and the stored settings. It does not return.
    public nonisolated static func main() {
        // `main.swift` runs on the main thread, but the compiler does not know that in Swift 5 mode.
        MainActor.assumeIsolated {
            let store = SettingsStore(defaults: .standard)
            let controller = AppController(
                saver: ScreenshotSaver(pasteboard: .general, folder: store.saveFolder),
                store: store
            )

            let app = NSApplication.shared
            app.delegate = controller
            // The same as `LSUIElement`: no Dock icon, also when the binary runs outside the bundle.
            app.setActivationPolicy(.accessory)
            // The delegate of the app is a weak reference.
            withExtendedLifetime(controller) { app.run() }
        }
    }

    // MARK: The life of the app

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if isSecondCopy() {
            NSApp.terminate(nil)
            return
        }

        let menu = StatusMenu(hotKey: settings.hotKey)
        menu.onTakeScreenshot = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + AppController.menuCloseDelay) {
                self?.startCapture()
            }
        }
        menu.onOpenFolder = { [weak self] in
            guard let self = self else { return }
            NSWorkspace.shared.open(self.saver.folder)
        }
        menu.onOpenSettings = { [weak self] in self?.openSettings() }
        menu.onQuit = { NSApp.terminate(nil) }
        statusMenu = menu

        hotKeyCenter.onHotKey = { [weak self] in
            MainActor.assumeIsolated { self?.startCapture() }
        }
        // The app continues to run when macOS refuses the hotkey. The menu still starts a capture,
        // and the settings window shows the red line.
        settings.registerHotKey()
        if settings.hotKeyProblem != nil {
            log.error("macOS refused the hotkey. A different app can have it.")
        }
        settings.onHotKeyChanged = { [weak self] hotKey in self?.statusMenu?.showHotKey(hotKey) }
        settings.onSaveFolderChanged = { [weak self] folder in self?.saver.folder = folder }
        settings.registerLoginItemAtFirstStart()

        if !ScreenRecordingPermission.isGranted {
            showPermissionWindow()
        }
    }

    /// The app lives in the menu bar. To close the settings window (or any window) does not quit it.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // A file write that started must complete, also when the user quits at once after Done.
        saver.waitForPendingWrites()
    }

    private func isSecondCopy() -> Bool {
        // The binary has no bundle identifier when it runs outside the bundle. Then there is no check.
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let copies = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        return copies.contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    // MARK: The capture

    /// The hotkey and "Take screenshot" come here.
    public func startCapture() {
        guard !isCapturing, NSApp.modalWindow == nil else { return }
        guard ScreenRecordingPermission.isGranted else {
            showPermissionWindow()
            return
        }
        permissionWindow?.close()
        isCapturing = true
        let start = DispatchTime.now()
        Task { await freezeAndShow(start: start) }
    }

    private func freezeAndShow(start: DispatchTime) async {
        do {
            let displays = try await capturer.freezeAllDisplays()
            let session = CaptureSession(displays: displays) { [weak self] outcome in
                self?.captureEnded(outcome)
            }
            self.session = session
            session.show()

            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            log.notice("Capture: \(milliseconds, format: .fixed(precision: 1)) ms from the hotkey to the visible windows, \(displays.count) displays")
        } catch {
            isCapturing = false
            showAlert("The screen capture failed", text: error.localizedDescription)
        }
    }

    private func captureEnded(_ outcome: CaptureOutcome) {
        // The session holds the frozen images. Free them now.
        session = nil
        isCapturing = false
        do {
            try saver.deliver(outcome) { [weak self] result in
                if case .failure(let failure) = result {
                    self?.fileNotSaved(failure)
                }
            }
        } catch {
            showAlert("The screen capture failed", text: error.localizedDescription)
        }
    }

    // MARK: The settings window

    private func showSettingsWindow() {
        // One window for the life of the app. A second "Settings…" shows the same window.
        let window = settingsWindow ?? SettingsWindowController(model: settings)
        settingsWindow = window
        window.show()
    }

    // MARK: Windows that tell a problem

    private func showPermissionWindow() {
        let window = permissionWindow ?? PermissionWindowController()
        permissionWindow = window
        window.show()
    }

    private func fileNotSaved(_ failure: ScreenshotSaver.FileFailure) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The file was not saved"
        alert.informativeText = """
            The image is on the clipboard. The app could not write to this folder:
            \(failure.folder.path)

            \(failure.underlying.localizedDescription)
            """
        alert.addButton(withTitle: "Choose folder…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        // The new folder is the save folder from now on, also after the app starts again.
        // The image of this capture goes there too.
        settings.setSaveFolder(folder)
        saver.writeFile(failure.png, date: failure.date) { [weak self] result in
            if case .failure(let failure) = result {
                self?.fileNotSaved(failure)
            }
        }
    }

    private func showAlert(_ message: String, text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
