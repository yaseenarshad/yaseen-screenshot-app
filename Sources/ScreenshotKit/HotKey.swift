import AppKit
import Carbon.HIToolbox

/// A key combination for the global hotkey.
/// Subissue 4 (YAZ-2768) adds the text form (for example "⇧⌘D") and the check that it is valid.
public struct HotKeyCombo: Equatable {
    /// The virtual key code (`kVK_…`).
    public var keyCode: UInt32
    /// Only Shift, Control, Option and Command count.
    public var modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
    }

    /// The hotkey that Yaseen used in Snip.
    public static let shiftCommandD = HotKeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: [.shift, .command])

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }
}

/// Registers one global hotkey with `RegisterEventHotKey`. This needs no permission.
public final class HotKeyCenter {
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
