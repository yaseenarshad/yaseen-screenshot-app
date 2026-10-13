import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The three rows of the settings window (D10).
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let chooseFolder: () -> Void

    var body: some View {
        Form {
            LabeledContent("Hotkey") {
                VStack(alignment: .trailing, spacing: 4) {
                    // The hotkey field: a click starts the recording, a second click stops it.
                    // The window controller gives the keys to the model while the field records.
                    Button(action: toggleRecording) {
                        Text(model.isRecording ? "Type a hotkey" : model.hotKey.text)
                            .frame(minWidth: 120)
                    }
                    if let problem = model.hotKeyProblem {
                        Text(problem).font(.callout).foregroundStyle(.red)
                    }
                }
            }

            LabeledContent("Save folder") {
                HStack {
                    Text(model.saveFolderText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Change…", action: chooseFolder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open at login", isOn: Binding(
                    get: { model.openAtLogin },
                    set: { model.setOpenAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!model.loginItemIsAvailable)

                if let note = model.loginItemNote {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
                if let problem = model.loginItemProblem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleRecording() {
        if model.isRecording {
            model.cancelRecording()
        } else {
            model.startRecording()
        }
    }
}

/// The one settings window of the app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let window: NSWindow
    private var keyMonitor: Any?

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.title = "Yaseen Screenshot settings"
        // The controller keeps the window, so "Settings…" shows the same window again.
        window.isReleasedWhenClosed = false
        window.delegate = self

        let host = NSHostingController(rootView: SettingsView(model: model) { [weak self] in
            self?.chooseFolder()
        })
        // The window follows the height of the form: a red line adds a row.
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        // The window has the size of the form before the first show. Then it opens in the middle
        // of the screen at its real size, and does not grow after it opens.
        window.setContentSize(host.view.fittingSize)
        window.center()

        // A monitor sees a key before the window does. Thus the field also gets a combination with Command,
        // which the window would handle as a key equivalent.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only plain values cross into the main actor: `NSEvent` is not `Sendable`.
            guard let combo = HotKeyCombo(keyDown: event) else { return event }
            let windowNumber = event.windowNumber
            let used = MainActor.assumeIsolated { self?.keyDown(combo, windowNumber: windowNumber) ?? false }
            // `nil` tells AppKit that the key is used.
            return used ? nil : event
        }
    }

    deinit {
        if let keyMonitor = keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// Shows the window in front of other apps. A second call shows the same window.
    func show() {
        model.refreshOpenAtLogin()
        // The app lives in the menu bar, so a different app is the active app. macOS can refuse
        // `NSApp.activate()` then, and the window opens behind that app. `orderFrontRegardless`
        // puts the window in front also when the app is not active.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Returns `true` when the key is used.
    private func keyDown(_ combo: HotKeyCombo, windowNumber: Int) -> Bool {
        guard windowNumber == window.windowNumber else { return false }
        if model.keyDown(combo) { return true }
        // The app has no main menu, so nothing else gives Command-W to the window.
        if combo == HotKeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: .command) {
            window.performClose(nil)
            return true
        }
        return false
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.saveFolder
        panel.prompt = "Choose"
        // A sheet, not a modal dialog: the hotkey still starts a capture while it is open.
        panel.beginSheetModal(for: window) { [weak self] response in
            // Cancel changes nothing.
            guard response == .OK, let folder = panel.url else { return }
            self?.model.setSaveFolder(folder)
        }
    }

    // MARK: NSWindowDelegate

    // A recording must not stay open with the global hotkey off.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // The user can come back from System Settings, Login Items.
        model.refreshOpenAtLogin()
    }
}
