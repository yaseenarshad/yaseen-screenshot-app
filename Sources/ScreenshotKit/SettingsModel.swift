import AppKit
import Carbon.HIToolbox

/// The state and the rules of the settings window, with no window and no view.
///
/// The model owns the changes of the settings: it registers the hotkey, stores the values and the
/// toolbar keys, and asks macOS for "open at login". The app and the window only call it. Thus a test proves the rules.
@MainActor
final class SettingsModel: ObservableObject {
    static let hotKeyInUseText = "That hotkey is in use."
    static let loginItemNotAvailableText = "Open at login works only in the installed app."
    static let loginItemNotChangedText = "macOS did not change this setting. Look at Login Items in System Settings."
    static let toolbarKeyNotValidText = "A toolbar key is one letter, digit or punctuation mark, with no ⌘, ⌃ or ⌥."

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
    /// The sound at the end of a capture.
    @Published private(set) var playSound: Bool
    /// The tool that is on when a box appears (YAZ-2879). `nil` is "None".
    @Published private(set) var startTool: Tool?
    /// The key of each toolbar action, in lower case (D5, YAZ-2872).
    @Published private var toolbarKeys: [ToolbarAction: String]
    /// The toolbar action whose key waits for a key. The global hotkey stays on: a toolbar key has
    /// no Command, Control or Option, so it cannot start a capture.
    @Published private(set) var recordingToolbarKey: ToolbarAction?
    /// The red line below the toolbar keys.
    @Published private(set) var toolbarKeyProblem: String?

    /// The menu shows the hotkey, so the app must know each change.
    var onHotKeyChanged: (HotKeyCombo) -> Void = { _ in }
    var onSaveFolderChanged: (URL) -> Void = { _ in }
    /// The app plays the sound one time when the switch goes on.
    var onPlaySoundChanged: (Bool) -> Void = { _ in }

    private let store: SettingsStore
    private let hotKeys: HotKeyRegistering
    private let loginItem: LoginItem

    init(store: SettingsStore, hotKeys: HotKeyRegistering, loginItem: LoginItem) {
        self.store = store
        self.hotKeys = hotKeys
        self.loginItem = loginItem
        hotKey = store.hotKey
        saveFolder = store.saveFolder
        playSound = store.playSound
        startTool = store.startTool
        toolbarKeys = store.toolbarKeys.all
        refreshOpenAtLogin()
    }

    // MARK: The hotkey

    /// Registers the current hotkey. The app calls this at the start.
    /// When macOS refuses, the app continues to run and the window shows the red line.
    func registerHotKey() {
        hotKeyProblem = hotKeys.register(hotKey) ? nil : SettingsModel.hotKeyInUseText
    }

    func startRecording() {
        guard !isRecording else { return }
        // One recorder at a time.
        recordingToolbarKey = nil
        // With the old hotkey still registered, macOS would start a capture and the field would not get the keys.
        hotKeys.unregister()
        hotKeyProblem = nil
        isRecording = true
    }

    /// Stops the recording and keeps the old hotkey, or the old toolbar key.
    func cancelRecording() {
        recordingToolbarKey = nil
        guard isRecording else { return }
        isRecording = false
        registerHotKey()
    }

    /// A key-down in the settings window. Returns `true` when the model used the key.
    /// `characters` is what the key types. Only a toolbar key needs it.
    func keyDown(_ combo: HotKeyCombo, characters: String? = nil) -> Bool {
        if let action = recordingToolbarKey {
            if combo.keyCode == UInt32(kVK_Escape) {
                cancelRecording()
            } else {
                recordToolbarKey(ToolbarKeys.key(typed: characters, modifiers: combo.modifiers), for: action)
            }
            return true
        }
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
            hotKeyProblem = SettingsModel.hotKeyInUseText
        }
        return true
    }

    // MARK: The toolbar keys

    func toolbarKey(_ action: ToolbarAction) -> String {
        toolbarKeys[action] ?? action.startKey
    }

    /// A click on the key of one toolbar action. It stops the other recorder: one records at a time.
    func startRecordingToolbarKey(_ action: ToolbarAction) {
        cancelRecording()
        toolbarKeyProblem = nil
        recordingToolbarKey = action
    }

    /// The recorder got a key. `key` is `nil` when the key press is not a valid toolbar key.
    /// A refused key leaves the old key, and the red line tells why.
    private func recordToolbarKey(_ key: String?, for action: ToolbarAction) {
        recordingToolbarKey = nil
        guard let key = key else {
            toolbarKeyProblem = SettingsModel.toolbarKeyNotValidText
            return
        }
        if let owner = ToolbarAction.all.first(where: { $0 != action && toolbarKey($0) == key }) {
            toolbarKeyProblem = SettingsModel.toolbarKeyTakenText(key, owner: owner)
            return
        }
        // A capture reads the store when it starts, so the key works in the next capture.
        store.toolbarKeys.set(key, for: action)
        toolbarKeys = store.toolbarKeys.all
        toolbarKeyProblem = nil
    }

    static func toolbarKeyTakenText(_ key: String, owner: ToolbarAction) -> String {
        "The key \(key.uppercased()) belongs to \(owner.name)."
    }

    /// "Reset to the start keys". The hotkey does not change.
    func resetToolbarKeys() {
        cancelRecording()
        store.toolbarKeys.reset()
        toolbarKeys = store.toolbarKeys.all
        toolbarKeyProblem = nil
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

    // MARK: The sound

    func setPlaySound(_ enabled: Bool) {
        // No change, no sound: the switch must not play it two times.
        guard enabled != playSound else { return }
        playSound = enabled
        store.playSound = enabled
        onPlaySoundChanged(enabled)
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
