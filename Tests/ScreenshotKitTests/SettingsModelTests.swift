import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import ScreenshotKit

/// A hotkey center that takes no real hotkey. It refuses the combinations in `refused`.
private final class FakeHotKeys: HotKeyRegistering {
    var refused: [HotKeyCombo] = []
    private(set) var registered: HotKeyCombo?

    func register(_ combo: HotKeyCombo) -> Bool {
        // The same as `HotKeyCenter`: a refused call leaves no hotkey.
        registered = refused.contains(combo) ? nil : combo
        return registered != nil
    }

    func unregister() { registered = nil }
}

/// A login item that never talks to macOS.
private final class FakeLoginItem: LoginItem {
    struct Refused: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    var isAvailable = true
    var isEnabled = false
    var refuses = false
    /// macOS gives no error, but the state does not change (the user must approve the app first).
    var ignores = false
    private(set) var calls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if refuses { throw Refused() }
        if !ignores { isEnabled = enabled }
    }
}

@MainActor
@Suite struct SettingsModelTests {
    private let controlOptionS = HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: [.control, .option])
    private let escape = HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: [])

    // YAZ-2866: the switch stores the value, and the app hears each change (it plays the sound on "on").
    @Test func theSoundSwitchStoresTheValueAndTellsTheApp() {
        withTemporaryDefaults { defaults in
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: FakeHotKeys(), loginItem: FakeLoginItem())
            var told: [Bool] = []
            model.onPlaySoundChanged = { told.append($0) }
            #expect(model.playSound == true)

            model.setPlaySound(false)
            #expect(model.playSound == false)
            #expect(SettingsStore(defaults: defaults).playSound == false)

            model.setPlaySound(true)
            #expect(told == [false, true])
            #expect(SettingsStore(defaults: defaults).playSound == true)
        }
    }

    // Rows 5 to 9 and 11.
    @Test func theFieldRecordsAValidCombinationAndSavesIt() {
        withTemporaryDefaults { defaults in
            let hotKeys = FakeHotKeys()
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: FakeLoginItem())
            var told: [HotKeyCombo] = []
            model.onHotKeyChanged = { told.append($0) }

            model.registerHotKey()
            #expect(hotKeys.registered == .shiftCommandD)
            // A key in the window while the field does not record is not for the model.
            #expect(model.keyDown(controlOptionS) == false)

            model.startRecording()
            #expect(model.isRecording)
            // While the field records, the app does not listen for the old hotkey.
            #expect(hotKeys.registered == nil)

            // Only Shift, or no modifier: not accepted, and the field continues to record.
            #expect(model.keyDown(HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: .shift)) == true)
            #expect(model.keyDown(HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: [])) == true)
            #expect(model.isRecording)
            #expect(hotKeys.registered == nil)
            #expect(told.isEmpty)

            #expect(model.keyDown(controlOptionS) == true)
            #expect(!model.isRecording)
            #expect(hotKeys.registered == controlOptionS)
            #expect(model.hotKey == controlOptionS)
            #expect(model.hotKey.text == "⌃⌥S")
            #expect(model.hotKeyProblem == nil)
            #expect(told == [controlOptionS])
            // A new store on the same suite: the hotkey is saved.
            #expect(SettingsStore(defaults: defaults).hotKey == controlOptionS)

            // Esc stops the recording. The old hotkey stays, and it listens again.
            model.startRecording()
            #expect(model.keyDown(escape) == true)
            #expect(!model.isRecording)
            #expect(hotKeys.registered == controlOptionS)
            #expect(SettingsStore(defaults: defaults).hotKey == controlOptionS)
            #expect(told == [controlOptionS])

            // The window closes during a recording: the same as Esc.
            model.startRecording()
            model.cancelRecording()
            #expect(hotKeys.registered == controlOptionS)
        }
    }

    // Rows 10 and 12.
    @Test func aCombinationThatADifferentAppHoldsKeepsTheOldHotKey() {
        withTemporaryDefaults { defaults in
            let hotKeys = FakeHotKeys()
            hotKeys.refused = [controlOptionS]
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: FakeLoginItem())
            var told: [HotKeyCombo] = []
            model.onHotKeyChanged = { told.append($0) }
            model.registerHotKey()

            model.startRecording()
            #expect(model.keyDown(controlOptionS) == true)
            #expect(!model.isRecording)
            #expect(model.hotKeyProblem == "That hotkey is in use.")
            #expect(model.hotKey == .shiftCommandD)
            #expect(hotKeys.registered == .shiftCommandD)
            #expect(SettingsStore(defaults: defaults).hotKey == .shiftCommandD)
            #expect(told.isEmpty)

            // The red line goes away when the next recording starts.
            model.startRecording()
            #expect(model.hotKeyProblem == nil)
            model.cancelRecording()
            #expect(model.hotKeyProblem == nil)

            // The stored hotkey cannot be registered at the start: the model tells it and nothing more.
            hotKeys.refused = [.shiftCommandD]
            let atStart = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: FakeLoginItem())
            atStart.registerHotKey()
            #expect(atStart.hotKeyProblem == "That hotkey is in use.")
            #expect(atStart.hotKey == .shiftCommandD)
            // A different combination still works then.
            atStart.startRecording()
            #expect(atStart.keyDown(HotKeyCombo(keyCode: UInt32(kVK_F6), modifiers: .command)) == true)
            #expect(atStart.hotKeyProblem == nil)
            #expect(hotKeys.registered?.text == "⌘F6")
        }
    }

    // Row 14, and subissue 1 row 33 (the new folder is stored).
    @Test func theSaveFolderShowsWithATildeAndAChangeIsSaved() {
        withTemporaryDefaults { defaults in
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: FakeHotKeys(), loginItem: FakeLoginItem())
            #expect(model.saveFolderText == "~/Pictures")

            var told: [URL] = []
            model.onSaveFolderChanged = { told.append($0) }
            let inHome = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/Shots", isDirectory: true)
            model.setSaveFolder(inHome)
            #expect(model.saveFolderText == "~/Desktop/Shots")
            #expect(told == [inHome])
            #expect(SettingsStore(defaults: defaults).saveFolder.path == inHome.path)

            model.setSaveFolder(URL(fileURLWithPath: "/Volumes/Disk/Shots", isDirectory: true))
            #expect(model.saveFolderText == "/Volumes/Disk/Shots")
        }
    }

    // Row 18.
    @Test func theFirstStartRegistersTheLoginItemOneTime() {
        withTemporaryDefaults { defaults in
            let loginItem = FakeLoginItem()
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: FakeHotKeys(), loginItem: loginItem)
            #expect(model.openAtLogin == false)

            model.registerLoginItemAtFirstStart()
            #expect(loginItem.calls == [true])
            #expect(model.openAtLogin == true)

            // The user turns it off in System Settings. A later start does not register again.
            loginItem.isEnabled = false
            let later = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: FakeHotKeys(), loginItem: loginItem)
            later.registerLoginItemAtFirstStart()
            #expect(loginItem.calls == [true])
            #expect(later.openAtLogin == false)
        }

        // The first registration fails: the app tells nothing, the switch shows off, and there is no second try.
        withTemporaryDefaults { defaults in
            let loginItem = FakeLoginItem()
            loginItem.refuses = true
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: FakeHotKeys(), loginItem: loginItem)
            model.registerLoginItemAtFirstStart()
            model.registerLoginItemAtFirstStart()
            #expect(loginItem.calls == [true])
            #expect(model.openAtLogin == false)
            #expect(model.loginItemProblem == nil)
        }
    }

    // Rows 19, 20 and 21.
    @Test func theSwitchShowsTheRealStateAndGoesBackWhenMacOSRefuses() {
        withTemporaryDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let loginItem = FakeLoginItem()
            let model = SettingsModel(store: store, hotKeys: FakeHotKeys(), loginItem: loginItem)

            // The stored value tells on (the default), but macOS tells off. The switch shows off.
            #expect(store.openAtLogin == true)
            #expect(model.openAtLogin == false)
            // A change in System Settings shows after a refresh.
            loginItem.isEnabled = true
            model.refreshOpenAtLogin()
            #expect(model.openAtLogin == true)

            model.setOpenAtLogin(false)
            #expect(loginItem.calls == [false])
            #expect(model.openAtLogin == false)
            #expect(store.openAtLogin == false)
            #expect(model.loginItemProblem == nil)

            // macOS refuses: the switch goes back, and the red line shows the reason.
            loginItem.refuses = true
            model.setOpenAtLogin(true)
            #expect(model.openAtLogin == false)
            #expect(model.loginItemProblem == "Operation not permitted")
            #expect(store.openAtLogin == false)

            // No error, but no change: the switch goes back with a line too.
            loginItem.refuses = false
            loginItem.ignores = true
            model.setOpenAtLogin(true)
            #expect(model.openAtLogin == false)
            #expect(model.loginItemProblem == SettingsModel.loginItemNotChangedText)

            // A change that works removes the red line.
            loginItem.ignores = false
            model.setOpenAtLogin(true)
            #expect(model.openAtLogin == true)
            #expect(model.loginItemProblem == nil)
            #expect(store.openAtLogin == true)
        }

        // Not from the `.app` bundle: the switch is off, a grey line tells why, and nothing calls macOS.
        withTemporaryDefaults { defaults in
            let loginItem = FakeLoginItem()
            loginItem.isAvailable = false
            loginItem.isEnabled = true
            let store = SettingsStore(defaults: defaults)
            let model = SettingsModel(store: store, hotKeys: FakeHotKeys(), loginItem: loginItem)
            model.registerLoginItemAtFirstStart()
            model.setOpenAtLogin(true)
            #expect(loginItem.calls.isEmpty)
            #expect(model.openAtLogin == false)
            #expect(model.loginItemIsAvailable == false)
            #expect(model.loginItemNote == "Open at login works only in the installed app.")
            // The one try is still free for the installed app.
            #expect(store.loginItemWasTried == false)
        }
    }

    // MARK: The toolbar keys (D5, YAZ-2872)

    private func key(_ code: Int, flags: NSEvent.ModifierFlags = []) -> HotKeyCombo {
        HotKeyCombo(keyCode: UInt32(code), modifiers: flags)
    }

    /// S23 to S27 of the working log YAZ-2873.
    @Test func theRecorderOfAToolbarKeyStoresAGoodKeyAndRefusesTheOthers() {
        withTemporaryDefaults { defaults in
            let hotKeys = FakeHotKeys()
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: FakeLoginItem())
            model.registerHotKey()
            let rectangle = ToolbarAction.tool(.rectangle)
            #expect(model.toolbarKey(rectangle) == "r")
            // With no recorder, the model does not use a plain key.
            #expect(!model.keyDown(key(kVK_ANSI_Q), characters: "q"))

            // S23: a good key is stored, and the capture reads it from the store.
            model.startRecordingToolbarKey(rectangle)
            #expect(model.recordingToolbarKey == rectangle)
            // The global hotkey stays on during the recording.
            #expect(hotKeys.registered == .shiftCommandD)
            #expect(model.keyDown(key(kVK_ANSI_Q, flags: .shift), characters: "Q"))
            #expect(model.recordingToolbarKey == nil && model.toolbarKeyProblem == nil)
            #expect(model.toolbarKey(rectangle) == "q")
            #expect(SettingsStore(defaults: defaults).toolbarKeys.action(for: "q") == rectangle)

            // S24: a key that a different action has. The old key stays.
            model.startRecordingToolbarKey(.tool(.ellipse))
            #expect(model.keyDown(key(kVK_ANSI_Q), characters: "q"))
            #expect(model.toolbarKeyProblem == "The key Q belongs to Rectangle.")
            #expect(model.toolbarKey(.tool(.ellipse)) == "o")

            // S25: a key with Command, and Space. The old key stays.
            model.startRecordingToolbarKey(.tool(.ellipse))
            #expect(model.toolbarKeyProblem == nil)
            #expect(model.keyDown(key(kVK_ANSI_E, flags: .command), characters: "e"))
            #expect(model.toolbarKeyProblem == SettingsModel.toolbarKeyNotValidText)
            model.startRecordingToolbarKey(.tool(.ellipse))
            #expect(model.keyDown(key(kVK_Space), characters: " "))
            #expect(model.toolbarKeyProblem == SettingsModel.toolbarKeyNotValidText)
            #expect(model.toolbarKey(.tool(.ellipse)) == "o")

            // S26: Esc stops the recorder with no change.
            model.startRecordingToolbarKey(.tool(.ellipse))
            #expect(model.keyDown(escape, characters: "\u{1b}"))
            #expect(model.recordingToolbarKey == nil && model.toolbarKey(.tool(.ellipse)) == "o")

            // One recorder at a time: the hotkey field stops the key recorder, and the reverse.
            model.startRecordingToolbarKey(.tool(.ellipse))
            model.startRecording()
            #expect(model.isRecording && model.recordingToolbarKey == nil)
            model.startRecordingToolbarKey(.tool(.ellipse))
            #expect(!model.isRecording && model.recordingToolbarKey == .tool(.ellipse))
            // The hotkey recorder paused the hotkey. The stop puts it back.
            #expect(hotKeys.registered == .shiftCommandD)

            // S27: the reset gives the start keys and removes the red line.
            #expect(model.keyDown(key(kVK_ANSI_Q), characters: "q"))
            #expect(model.toolbarKeyProblem != nil)
            model.resetToolbarKeys()
            #expect(model.toolbarKey(rectangle) == "r" && model.toolbarKeyProblem == nil)
            #expect(SettingsStore(defaults: defaults).toolbarKeys.action(for: "r") == rectangle)
        }
    }

    /// D6 and S22 (YAZ-2879): the choice is stored, and a new store gives it back.
    @Test func theToolAfterTheBoxIsStored() {
        withTemporaryDefaults { defaults in
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: FakeHotKeys(), loginItem: FakeLoginItem())
            #expect(model.startTool == .rectangle)
            model.setStartTool(.ellipse)
            #expect(model.startTool == .ellipse && SettingsStore(defaults: defaults).startTool == .ellipse)
            model.setStartTool(nil)
            #expect(model.startTool == nil && SettingsStore(defaults: defaults).startTool == nil)
        }
    }

    /// The form lays out with no window. The lines for a problem make it higher.
    @Test func theFormHasASizeAndGrowsWithTheProblemLines() {
        withTemporaryDefaults { defaults in
            let hotKeys = FakeHotKeys()
            let loginItem = FakeLoginItem()
            let model = SettingsModel(store: SettingsStore(defaults: defaults), hotKeys: hotKeys, loginItem: loginItem)
            @MainActor func size() -> CGSize {
                NSHostingView(rootView: SettingsView(model: model, chooseFolder: {})).fittingSize
            }
            let plain = size()
            #expect(plain.width == 460)
            // The toolbar keys make the form higher. It still fits a small screen with no scroll.
            #expect(plain.height > 300 && plain.height < 640)

            hotKeys.refused = [.shiftCommandD]
            model.registerHotKey()
            let withHotKeyLine = size().height
            #expect(withHotKeyLine > plain.height)

            loginItem.refuses = true
            model.setOpenAtLogin(true)
            #expect(size().height > withHotKeyLine)
        }
    }
}
