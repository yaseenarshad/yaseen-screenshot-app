import AppKit
import Carbon.HIToolbox

/// The state and the rules of the settings window, with no window and no view.
///
/// The model owns the changes of the three settings: it registers the hotkey, stores the values,
/// and asks macOS for "open at login". The app and the window only call it. Thus a test proves the rules.
@MainActor
final class SettingsModel: ObservableObject {
    static let shortcutInUseText = "That shortcut is in use."
    static let loginItemNotAvailableText = "Open at login works only in the installed app."
    static let loginItemNotChangedText = "macOS did not change this setting. Look at Login Items in System Settings."

    @Published private(set) var hotKey: HotKeyCombo
    /// True while the hotkey field waits for a combination. The global hotkey is off during that time.
    @Published private(set) var isRecording = false
    /// The red line below the hotkey field.
    @Published private(set) var hotKeyProblem: String?
    @Published private(set) var saveFolder: URL
    /// The real state from macOS, not the stored value.
    @Published private(set) var openAtLogin = false
    /// The red line below the switch.
    @Published private(set) var loginItemProblem: String?

    /// The menu shows the hotkey, so the app must know each change.
    var onHotKeyChanged: (HotKeyCombo) -> Void = { _ in }
    var onSaveFolderChanged: (URL) -> Void = { _ in }

    private let store: SettingsStore
    private let hotKeys: HotKeyRegistering
    private let loginItem: LoginItem

    init(store: SettingsStore, hotKeys: HotKeyRegistering, loginItem: LoginItem) {
        self.store = store
        self.hotKeys = hotKeys
        self.loginItem = loginItem
        hotKey = store.hotKey
        saveFolder = store.saveFolder
        refreshOpenAtLogin()
    }

    // MARK: The hotkey

    /// Registers the current hotkey. The app calls this at the start.
    /// When macOS refuses, the app continues to run and the window shows the red line.
    func registerHotKey() {
        hotKeyProblem = hotKeys.register(hotKey) ? nil : SettingsModel.shortcutInUseText
    }

    func startRecording() {
        guard !isRecording else { return }
        // With the old hotkey still registered, macOS would start a capture and the field would not get the keys.
        hotKeys.unregister()
        hotKeyProblem = nil
        isRecording = true
    }

    /// Stops the recording and keeps the old hotkey.
    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        registerHotKey()
    }

    /// A key-down in the settings window. Returns `true` when the model used the key.
    func keyDown(_ combo: HotKeyCombo) -> Bool {
        guard isRecording else { return false }
        if combo.keyCode == UInt32(kVK_Escape) {
            cancelRecording()
            return true
        }
        // Not valid (only Shift, or no modifier): the field continues to record.
        guard combo.isValid else { return true }

        isRecording = false
        if hotKeys.register(combo) {
            // Save only a combination that macOS accepted.
            hotKey = combo
            store.hotKey = combo
            hotKeyProblem = nil
            onHotKeyChanged(combo)
        } else {
            // The failed call left no hotkey registered. Put the old one back.
            _ = hotKeys.register(hotKey)
            hotKeyProblem = SettingsModel.shortcutInUseText
        }
        return true
    }

    // MARK: The save folder

    /// The path with `~` for the home folder.
    var saveFolderText: String {
        (saveFolder.path as NSString).abbreviatingWithTildeInPath
    }

    func setSaveFolder(_ folder: URL) {
        saveFolder = folder
        store.saveFolder = folder
        onSaveFolderChanged(folder)
    }

    // MARK: Open at login

    var loginItemIsAvailable: Bool { loginItem.isAvailable }

    /// The grey line below the switch.
    var loginItemNote: String? {
        loginItem.isAvailable ? nil : SettingsModel.loginItemNotAvailableText
    }

    /// Reads the real state again. The user can change it in System Settings while the app runs.
    func refreshOpenAtLogin() {
        openAtLogin = loginItem.isAvailable && loginItem.isEnabled
    }

    /// The first start registers the app one time (the default is on). A failure tells nothing.
    /// Safe to call at each start: after the first call it does nothing.
    func registerLoginItemAtFirstStart() {
        // Outside the bundle there is nothing to register. Do not use up the one try there.
        guard loginItem.isAvailable, !store.loginItemWasTried else { return }
        store.loginItemWasTried = true
        if store.openAtLogin, !loginItem.isEnabled {
            try? loginItem.setEnabled(true)
        }
        refreshOpenAtLogin()
    }

    /// The switch. When macOS refuses the change, the switch goes back and the red line shows the reason.
    func setOpenAtLogin(_ enabled: Bool) {
        guard loginItem.isAvailable else { return }
        do {
            try loginItem.setEnabled(enabled)
            loginItemProblem = nil
        } catch {
            loginItemProblem = error.localizedDescription
        }
        refreshOpenAtLogin()
        if openAtLogin == enabled {
            store.openAtLogin = enabled
        } else if loginItemProblem == nil {
            // macOS gave no error but the state is not the new one (for example, the user must approve the app).
            loginItemProblem = SettingsModel.loginItemNotChangedText
        }
    }
}
