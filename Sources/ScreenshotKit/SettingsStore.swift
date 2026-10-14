import AppKit

/// The four settings of the app (D10, YAZ-2866), in `UserDefaults`.
///
/// The `UserDefaults` is a parameter, so a test gives one that keeps its values in memory.
/// A value that is missing or broken gives the default. The store never fails.
public final class SettingsStore {
    private enum Key {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let saveFolder = "saveFolder"
        static let openAtLogin = "openAtLogin"
        static let playSound = "playSound"
        static let loginItemWasTried = "loginItemWasTried"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// `~/Pictures`: the folder that Yaseen used in Snip.
    public static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    }

    /// The global hotkey. The default is Shift-Command-D.
    public var hotKey: HotKeyCombo {
        get {
            guard
                let code = defaults.object(forKey: Key.hotKeyCode) as? Int,
                let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int,
                // A virtual key code is one byte.
                (0...0xFF).contains(code), modifiers >= 0
            else { return .shiftCommandD }
            let combo = HotKeyCombo(
                keyCode: UInt32(code),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers))
            )
            return combo.isValid ? combo : .shiftCommandD
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(newValue.modifiers.rawValue), forKey: Key.hotKeyModifiers)
        }
    }

    /// The folder for the files. The default is `~/Pictures`.
    /// The folder can be missing on disk. Then the save shows its alert (subissue 1, row 33).
    public var saveFolder: URL {
        get {
            guard let path = defaults.object(forKey: Key.saveFolder) as? String, path.hasPrefix("/") else {
                return SettingsStore.defaultSaveFolder
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: Key.saveFolder) }
    }

    /// What the user wants. The default is on. The real state is in macOS (`LoginItem.isEnabled`).
    public var openAtLogin: Bool {
        get { defaults.object(forKey: Key.openAtLogin) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.openAtLogin) }
    }

    /// The sound at the end of a capture. The default is on, as in the macOS screenshot.
    public var playSound: Bool {
        get { defaults.object(forKey: Key.playSound) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.playSound) }
    }

    /// The keys of the toolbar (D1, YAZ-2872), in their own store on the same `UserDefaults`.
    var toolbarKeys: ToolbarKeys { ToolbarKeys(defaults: defaults) }

    /// True after the first start tried to register the app as a login item. The app tries one time only.
    public var loginItemWasTried: Bool {
        get { defaults.object(forKey: Key.loginItemWasTried) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.loginItemWasTried) }
    }
}
