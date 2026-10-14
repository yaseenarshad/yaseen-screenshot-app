import AppKit

/// The 17 actions of the toolbar that have a key (D4, YAZ-2872): Select, the seven tools, the
/// three sizes and the six colours. Undo, Cancel and Done have fixed keys.
public enum ToolbarAction: Hashable {
    case select
    case tool(Tool)
    case size(MarkSize)
    case color(MarkColor)

    /// The three groups, in the order of the toolbar. The settings window shows them in this order.
    static let groups: [(title: String, actions: [ToolbarAction])] = [
        ("Tools", [.select] + Tool.allCases.map { .tool($0) }),
        ("Sizes", MarkSize.allCases.map { .size($0) }),
        ("Colours", MarkColor.allCases.map { .color($0) }),
    ]

    static let all = groups.flatMap { $0.actions }

    /// The name of the button.
    var name: String {
        switch self {
        case .select: return "Select"
        case .tool(let tool): return tool.name
        case .size(let size): return size.name
        case .color(let color): return color.name
        }
    }

    /// The name of the action in the stored value.
    var id: String {
        switch self {
        case .select: return "select"
        case .tool(let tool): return "tool." + tool.name.lowercased()
        case .size(let size): return "size." + size.name.lowercased()
        case .color(let color): return "color." + color.name.lowercased()
        }
    }

    /// The key at the start: the letters of the Draw app for the tools, 1 to 3 for the sizes,
    /// and 4 to 9 for the colours (D4).
    var startKey: String {
        switch self {
        case .select: return "v"
        case .tool(.rectangle): return "r"
        case .tool(.ellipse): return "o"
        case .tool(.arrow): return "a"
        case .tool(.pen): return "w"
        case .tool(.highlight): return "h"
        case .tool(.text): return "t"
        case .tool(.number): return "n"
        case .size(.thin): return "1"
        case .size(.medium): return "2"
        case .size(.thick): return "3"
        case .color(.red): return "4"
        case .color(.amber): return "5"
        case .color(.green): return "6"
        case .color(.blue): return "7"
        case .color(.black): return "8"
        case .color(.white): return "9"
        }
    }
}

/// The keys of the toolbar (D1), in `UserDefaults`. A key is one character, in lower case.
///
/// The settings window writes a key here. A capture reads the keys when a key arrives, and its
/// toolbar reads them one time to show them. Thus a new key works in the next capture.
///
/// The keys are not global hotkeys. Nothing is registered for them, so they cost nothing outside
/// a capture. The store never fails: stored keys that are not valid give the start keys.
public struct ToolbarKeys {
    /// The second key of the Pen, as in the Draw app. It works only while no action has this key.
    static let secondPenKey = "p"
    private static let defaultsKey = "toolbarKeys"

    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The toolbar key that a key press types. `nil` when the press is not a toolbar key.
    ///
    /// The key is the character that the press types, not the position on the keyboard.
    /// The case of a letter does not count, so Shift and Caps Lock change nothing.
    /// A press with Command, Control or Option is not a toolbar key. Space, Return, Tab, Esc,
    /// Delete, an arrow key and a function key type no letter, digit or punctuation mark.
    static func key(typed characters: String?, modifiers: NSEvent.ModifierFlags = []) -> String? {
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
              let key = characters?.lowercased(), key.count == 1, let character = key.first,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        else { return nil }
        return key
    }

    /// The key of each action now.
    var all: [ToolbarAction: String] {
        var keys: [ToolbarAction: String] = [:]
        for action in ToolbarAction.all { keys[action] = action.startKey }
        guard let stored = defaults.object(forKey: ToolbarKeys.defaultsKey) as? [String: String] else { return keys }
        let start = keys
        for action in ToolbarAction.all {
            guard let value = stored[action.id] else { continue }
            // A stored key that is not valid: the app uses the start keys.
            guard let key = ToolbarKeys.key(typed: value) else { return start }
            keys[action] = key
        }
        // Two actions with the same key: the app uses the start keys.
        return Set(keys.values).count == keys.count ? keys : start
    }

    /// The action of a typed key, if the key is a toolbar key now.
    func action(for key: String) -> ToolbarAction? {
        let keys = all
        if let action = ToolbarAction.all.first(where: { keys[$0] == key }) { return action }
        return key == ToolbarKeys.secondPenKey ? .tool(.pen) : nil
    }

    /// Stores a new key for one action. The caller makes sure that the key is valid and that no
    /// other action has it.
    func set(_ key: String, for action: ToolbarAction) {
        var stored: [String: String] = [:]
        for (each, value) in all { stored[each.id] = value }
        stored[action.id] = key
        defaults.set(stored, forKey: ToolbarKeys.defaultsKey)
    }

    /// "Reset to the start keys".
    func reset() {
        defaults.removeObject(forKey: ToolbarKeys.defaultsKey)
    }
}
