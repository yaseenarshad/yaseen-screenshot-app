import AppKit
import Carbon.HIToolbox

/// A key combination for the global hotkey.
public struct HotKeyCombo: Equatable {
    /// The virtual key code (`kVK_…`).
    public var keyCode: UInt32
    /// Only Shift, Control, Option and Command count.
    public var modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
    }

    /// The combination of a key-down event. `nil` for any other event.
    public init?(keyDown event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
    }

    /// The hotkey that Yaseen used in Snip.
    public static let shiftCommandD = HotKeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: [.shift, .command])

    /// A hotkey needs Command, Control or Option. With only Shift, or with no modifier,
    /// the hotkey would take a key that the user types in text.
    /// Escape is never a hotkey: it stops the recording in the settings window.
    public var isValid: Bool {
        keyCode != UInt32(kVK_Escape) && !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    /// The text form, for example "⇧⌘D". The modifiers are in the order that macOS uses: ⌃⌥⇧⌘.
    public var text: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + (HotKeyCombo.keys[keyCode]?.name ?? "Key \(keyCode)")
    }

    /// The key for `NSMenuItem.keyEquivalent`. Empty for a key that a menu cannot show.
    var menuKeyEquivalent: String {
        HotKeyCombo.keys[keyCode]?.menu ?? ""
    }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    // MARK: The names of the keys

    private struct Key {
        /// The name in the text form.
        let name: String
        /// The character that a menu item needs to show the key.
        let menu: String
    }

    /// The names are those of the US keyboard layout. A key code is a position on the keyboard,
    /// so on a different layout the hotkey is still the same physical key.
    private static let keys: [UInt32: Key] = {
        var keys: [UInt32: Key] = [:]
        func add(_ code: Int, _ name: String, menu: String? = nil) {
            keys[UInt32(code)] = Key(name: name, menu: menu ?? name.lowercased())
        }
        func add(_ code: Int, _ name: String, functionKey: Int) {
            add(code, name, menu: Unicode.Scalar(UInt32(functionKey)).map { String(Character($0)) })
        }

        let letters = [
            kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
            kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
            kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
            kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
        ]
        for (code, letter) in zip(letters, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") { add(code, String(letter)) }

        let digits = [
            kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
            kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        ]
        for (code, digit) in zip(digits, "0123456789") { add(code, String(digit)) }

        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() {
            add(code, "F\(index + 1)", functionKey: NSF1FunctionKey + index)
        }

        let punctuation: [(Int, String)] = [
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
            (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`"),
        ]
        for (code, name) in punctuation { add(code, name) }

        add(kVK_Space, "Space", menu: " ")
        add(kVK_Return, "↩", menu: "\r")
        add(kVK_Tab, "⇥", menu: "\t")
        add(kVK_Delete, "⌫", menu: "\u{8}")
        add(kVK_Escape, "⎋", menu: "\u{1B}")
        add(kVK_ForwardDelete, "⌦", functionKey: NSDeleteFunctionKey)
        add(kVK_LeftArrow, "←", functionKey: NSLeftArrowFunctionKey)
        add(kVK_RightArrow, "→", functionKey: NSRightArrowFunctionKey)
        add(kVK_UpArrow, "↑", functionKey: NSUpArrowFunctionKey)
        add(kVK_DownArrow, "↓", functionKey: NSDownArrowFunctionKey)
        add(kVK_Home, "↖", functionKey: NSHomeFunctionKey)
        add(kVK_End, "↘", functionKey: NSEndFunctionKey)
        add(kVK_PageUp, "⇞", functionKey: NSPageUpFunctionKey)
        add(kVK_PageDown, "⇟", functionKey: NSPageDownFunctionKey)
        return keys
    }()
}

/// The two calls that the settings need from `HotKeyCenter`.
/// A test uses a fake one, so it never takes a real global hotkey.
public protocol HotKeyRegistering: AnyObject {
    /// Replaces the registered hotkey. Returns `false` when macOS refuses the combination.
    /// After a `false`, no hotkey is registered.
    func register(_ combo: HotKeyCombo) -> Bool
    func unregister()
}

/// Registers one global hotkey with `RegisterEventHotKey`. This needs no permission.
public final class HotKeyCenter: HotKeyRegistering {
    /// Runs on the main thread each time the user presses the hotkey.
    public var onHotKey: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    public init() {}

    deinit {
        unregister()
        if let handler = handler { RemoveEventHandler(handler) }
    }

    /// Replaces the registered hotkey. Returns `false` when macOS refuses the combination.
    @discardableResult
    public func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        guard installHandler() else { return false }
        let id = EventHotKeyID(signature: 0x5953_484B /* "YSHK" */, id: 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else { return false }
        hotKey = reference
        return true
    }

    public func unregister() {
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The callback is a C function. It gets `self` back through the user data pointer.
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData = userData else { return noErr }
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().onHotKey?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        return status == noErr
    }
}
