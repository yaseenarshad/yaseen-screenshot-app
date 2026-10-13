import AppKit

/// The place of the menu bar icon at the first start.
///
/// macOS puts a new icon at the left end of the icons. On a MacBook with a notch and a full menu
/// bar, that place is behind the notch, and the user never sees the icon. macOS reads the place
/// of an icon from the preferences of the app, so the app writes a place before it makes the icon.
enum MenuBarIconPlace {
    /// The autosave name of the status item. It is the name that macOS gives the first status
    /// item of an app. The app sets it, so the key below does not depend on the order in which
    /// the app makes its items. A different name loses the place that the user has now.
    static let autosaveName = "Item-0"
    /// The key that macOS reads and writes for a status item with this autosave name.
    static let key = "NSStatusItem Preferred Position " + autosaveName
    /// Points from the right edge of the screen. Tested on a MacBook Pro with a notch and a full
    /// menu bar: the icon shows to the right of the notch.
    static let firstPosition: Double = 420

    /// Writes the first place, only when no place is stored. A user who moved the icon
    /// (hold Command and drag) keeps that place at each later start.
    static func writeFirstPosition(to defaults: UserDefaults) {
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(firstPosition, forKey: key)
    }
}

/// The menu bar icon and its four rows (D10).
@MainActor
final class StatusMenu: NSObject {
    var onTakeScreenshot: () -> Void = {}
    var onOpenFolder: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    private let statusItem: NSStatusItem
    private let takeScreenshotRow = NSMenuItem(title: "Take screenshot", action: #selector(takeScreenshot), keyEquivalent: "")

    /// `defaults` are the preferences of the app, where macOS keeps the place of the icon.
    init(hotKey: HotKeyCombo, defaults: UserDefaults) {
        // The order matters: macOS reads the place when the item is made.
        MenuBarIconPlace.writeFirstPosition(to: defaults)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = MenuBarIconPlace.autosaveName

        // A template image: macOS colours it for a light and for a dark menu bar.
        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Yaseen Screenshot")
        icon?.isTemplate = true
        statusItem.button?.image = icon

        let menu = NSMenu()
        takeScreenshotRow.target = self
        showHotKey(hotKey)
        menu.addItem(takeScreenshotRow)
        menu.addItem(row("Open screenshots folder", #selector(openFolder)))
        menu.addItem(row("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(row("Quit", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    /// "Take screenshot" shows the hotkey on its right side, as a menu shows a key equivalent.
    func showHotKey(_ hotKey: HotKeyCombo) {
        takeScreenshotRow.keyEquivalent = hotKey.menuKeyEquivalent
        takeScreenshotRow.keyEquivalentModifierMask = hotKey.modifiers
    }

    private func row(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func takeScreenshot() { onTakeScreenshot() }
    @objc private func openFolder() { onOpenFolder() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { onQuit() }
}
