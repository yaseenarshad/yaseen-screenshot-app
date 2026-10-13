import Foundation
import ServiceManagement

/// "Open at login" of macOS.
///
/// This is a protocol for one reason: the tests and `swift run` must never register a real login item.
public protocol LoginItem {
    /// False when the app does not run from a `.app` bundle. Then macOS has nothing to register.
    var isAvailable: Bool { get }
    /// The real state from macOS.
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// The real one: `SMAppService.mainApp`.
public struct SystemLoginItem: LoginItem {
    public init() {}

    public var isAvailable: Bool {
        // `swift run` starts the bare binary. Its "bundle" is the build folder.
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    public var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
