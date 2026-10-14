import AppKit
import Testing
@testable import ScreenshotKit

/// The store of the toolbar keys (D1 and D4, YAZ-2872), in memory.
@Suite struct ToolbarKeysTests {
    @Test func theStartKeysAreTheKeysOfTheDrawApp() {
        let keys = ToolbarKeys(defaults: MemoryDefaults()).all
        #expect(keys.count == 17)
        #expect(ToolbarAction.all.map { keys[$0]! }.joined() == "vroawhtn123456789")
        #expect(ToolbarAction.groups.map(\.title) == ["Tools", "Sizes", "Colours"])
    }

    @Test func aStoredKeyIsUsedAndABrokenValueGivesTheStartKeys() {
        let defaults = MemoryDefaults()
        let store = ToolbarKeys(defaults: defaults)
        store.set("q", for: .tool(.rectangle))
        #expect(store.all[.tool(.rectangle)] == "q")
        #expect(store.action(for: "q") == .tool(.rectangle))
        #expect(store.action(for: "r") == nil)

        // S28: a value that is not valid, and two actions with the same key.
        defaults.set(["tool.rectangle": "qq"], forKey: "toolbarKeys")
        #expect(store.all == ToolbarKeys(defaults: MemoryDefaults()).all)
        defaults.set(["tool.rectangle": "o"], forKey: "toolbarKeys")
        #expect(store.all[.tool(.rectangle)] == "r" && store.all[.tool(.ellipse)] == "o")
        defaults.set("not a dictionary", forKey: "toolbarKeys")
        #expect(store.all[.select] == "v")

        store.set("q", for: .tool(.rectangle))
        store.reset()
        #expect(store.all[.tool(.rectangle)] == "r")
    }

    @Test func pIsTheSecondKeyOfThePenOnlyWhileNoActionHasIt() {
        let store = ToolbarKeys(defaults: MemoryDefaults())
        #expect(store.action(for: "p") == .tool(.pen))
        store.set("p", for: .tool(.arrow))
        #expect(store.action(for: "p") == .tool(.arrow))
    }

    /// S14, S15 and the keys that type no character.
    @Test func whatAKeyPressTypes() {
        #expect(ToolbarKeys.key(typed: "R") == "r")
        #expect(ToolbarKeys.key(typed: "R", modifiers: .shift) == "r")
        #expect(ToolbarKeys.key(typed: "7") == "7")
        #expect(ToolbarKeys.key(typed: ",") == ",")
        #expect(ToolbarKeys.key(typed: "r", modifiers: .command) == nil)
        #expect(ToolbarKeys.key(typed: "r", modifiers: .control) == nil)
        #expect(ToolbarKeys.key(typed: "r", modifiers: .option) == nil)
        for typed in [" ", "\r", "\t", "\u{1b}", "\u{7f}", "\u{F700}", "", "ab", nil] {
            #expect(ToolbarKeys.key(typed: typed) == nil, "\(String(describing: typed))")
        }
    }
}
