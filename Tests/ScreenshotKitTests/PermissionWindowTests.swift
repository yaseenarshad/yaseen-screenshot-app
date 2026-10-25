import AppKit
import Testing
@testable import ScreenshotKit

/// The window that asks for the Screen Recording permission (YAZ-3318). macOS tells the app about
/// a new permission only when the app starts. Thus the button quits the app and opens it again.
/// The tests give their own check and their own relaunch, so a click quits nothing. No window is shown.
@MainActor @Suite struct PermissionWindowTests {
    private func buttons(in controller: PermissionWindowController) -> [NSButton] {
        func buttons(in view: NSView) -> [NSButton] {
            view.subviews.flatMap { ([$0 as? NSButton].compactMap { $0 }) + buttons(in: $0) }
        }
        return controller.window?.contentView.map { buttons(in: $0) } ?? []
    }

    private func button(_ title: String, in controller: PermissionWindowController) throws -> NSButton {
        try #require(buttons(in: controller).first { $0.title == title }, "no button \(title)")
    }

    private func texts(in controller: PermissionWindowController) -> [String] {
        func fields(in view: NSView) -> [NSTextField] {
            view.subviews.flatMap { ([$0 as? NSTextField].compactMap { $0 }) + fields(in: $0) }
        }
        return controller.window?.contentView.map { fields(in: $0).map(\.stringValue) } ?? []
    }

    @Test func quitAndReopenStartsTheAppAgainWhileThePermissionIsOff() throws {
        var relaunches = 0
        let controller = PermissionWindowController(isGranted: { false }, relaunch: { relaunches += 1; return true })
        #expect(buttons(in: controller).map(\.title).sorted() == ["Open System Settings", "Quit and Reopen"])
        let reopen = try button("Quit and Reopen", in: controller)
        NSApplication.shared.setActivationPolicy(.accessory)
        #expect(reopen.sendAction(reopen.action, to: reopen.target))
        #expect(relaunches == 1)
        #expect(texts(in: controller).contains { $0.contains("then click Quit and Reopen") })
    }

    @Test func quitAndReopenDoesNothingMoreWhenThePermissionIsOnAndTellsWhenTheAppCannotOpenAgain() throws {
        // The app has the permission already: no new start.
        var relaunches = 0
        let granted = PermissionWindowController(isGranted: { true }, relaunch: { relaunches += 1; return true })
        let reopen = try button("Quit and Reopen", in: granted)
        NSApplication.shared.setActivationPolicy(.accessory)
        #expect(reopen.sendAction(reopen.action, to: reopen.target))
        #expect(relaunches == 0)

        // The app cannot open itself again: it does not quit, and the window tells what to do.
        let failing = PermissionWindowController(isGranted: { false }, relaunch: { false })
        let button = try button("Quit and Reopen", in: failing)
        #expect(button.sendAction(button.action, to: button.target))
        #expect(texts(in: failing).contains("The app could not open again. Quit it from the menu bar, and open it again."))
    }
}
