import AppKit
import Carbon.HIToolbox
import Testing
@testable import ScreenshotKit

/// A `UserDefaults` that keeps its values in memory only.
///
/// A real suite (`UserDefaults(suiteName:)`) is not possible here: macOS writes a file for it in
/// `~/Library/Preferences`, and writes an empty file again some seconds after `removePersistentDomain`.
/// The tests must leave no file.
final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() {
        // The name is never used: each call that the app makes is overridden below.
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Double, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}

/// Runs `body` with a `UserDefaults` that only this test uses.
func withTemporaryDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    try body(MemoryDefaults())
}

@Suite struct SettingsStoreTests {
    @Test func theDefaults() {
        withTemporaryDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            #expect(store.hotKey == HotKeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: [.shift, .command]))
            #expect(store.saveFolder.path == NSHomeDirectory() + "/Pictures")
            #expect(store.openAtLogin == true)
            #expect(store.loginItemWasTried == false)
            #expect(store.playSound == true)
        }
    }

    @Test func aWrittenValueComesBackFromANewStoreOnTheSameDefaults() {
        withTemporaryDefaults { defaults in
            let combo = HotKeyCombo(keyCode: UInt32(kVK_F6), modifiers: [.control, .option])
            let folder = URL(fileURLWithPath: "/tmp/Screenshots of Yaseen", isDirectory: true)

            let first = SettingsStore(defaults: defaults)
            first.hotKey = combo
            first.saveFolder = folder
            first.openAtLogin = false
            first.loginItemWasTried = true
            first.playSound = false

            let second = SettingsStore(defaults: defaults)
            #expect(second.hotKey == combo)
            #expect(second.saveFolder.path == folder.path)
            #expect(second.openAtLogin == false)
            #expect(second.loginItemWasTried == true)
            #expect(second.playSound == false)
        }
    }

    @Test func aBrokenStoredValueGivesTheDefault() {
        withTemporaryDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            // Each case: the two hotkey values as they are on disk.
            let brokenHotKeys: [(code: Any?, modifiers: Any?)] = [
                ("d", Int(NSEvent.ModifierFlags.command.rawValue)),      // the code is not a number
                (kVK_ANSI_A, "command"),                                  // the modifiers are not a number
                (kVK_ANSI_A, nil),                                        // one value is missing
                (-1, Int(NSEvent.ModifierFlags.command.rawValue)),       // not a key code
                (4000, Int(NSEvent.ModifierFlags.command.rawValue)),     // not a key code
                (kVK_ANSI_A, -5),                                         // not a set of modifiers
                (kVK_ANSI_A, Int(NSEvent.ModifierFlags.shift.rawValue)), // only Shift is not a valid hotkey
                (kVK_ANSI_A, 0),                                          // no modifier
                (kVK_Escape, Int(NSEvent.ModifierFlags.command.rawValue)), // Escape is reserved
            ]
            for broken in brokenHotKeys {
                defaults.set(broken.code, forKey: "hotKeyCode")
                defaults.set(broken.modifiers, forKey: "hotKeyModifiers")
                #expect(store.hotKey == .shiftCommandD, "\(broken)")
            }

            for broken in [42, "", "Pictures/relative", ["a", "b"]] as [Any] {
                defaults.set(broken, forKey: "saveFolder")
                #expect(store.saveFolder == SettingsStore.defaultSaveFolder, "\(broken)")
            }

            defaults.set("perhaps", forKey: "openAtLogin")
            #expect(store.openAtLogin == true)
            defaults.set(["x"], forKey: "loginItemWasTried")
            #expect(store.loginItemWasTried == false)
            defaults.set("perhaps", forKey: "playSound")
            #expect(store.playSound == true)

            // The start tool (D1, YAZ-2879): the default and a broken value give the Rectangle.
            #expect(store.startTool == .rectangle)
            defaults.set("square", forKey: "startTool")
            #expect(store.startTool == .rectangle)
            defaults.set(7, forKey: "startTool")
            #expect(store.startTool == .rectangle)
            store.startTool = nil
            #expect(defaults.object(forKey: "startTool") as? String == "none")
            #expect(store.startTool == nil)
            store.startTool = .highlight
            #expect(SettingsStore(defaults: defaults).startTool == .highlight)

            // The numbers 1 and 0 are a switch value, as the `defaults` command writes them.
            defaults.set(NSNumber(value: 0), forKey: "openAtLogin")
            #expect(store.openAtLogin == false)
        }
    }
}
