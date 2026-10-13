import AppKit

/// The menu bar icon and its four rows (D10).
@MainActor
final class StatusMenu: NSObject {
    var onTakeScreenshot: () -> Void = {}
    var onOpenFolder: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let takeScreenshotRow = NSMenuItem(title: "Take screenshot", action: #selector(takeScreenshot), keyEquivalent: "")

    init(hotKey: HotKeyCombo) {
        super.init()

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
