import Foundation
import Testing
@testable import ScreenshotKit

/// The place of the menu bar icon (the finding "the menu bar icon was behind the notch" on YAZ-2768).
/// The tests make no status item: a status item shows in the real menu bar.
@Suite struct MenuBarIconPlaceTests {
    /// The key as macOS spells it, not as the app builds it. Yaseen's Mac has a place under this
    /// key already. A change of the autosave name fails here, because it loses that place.
    let key = "NSStatusItem Preferred Position Item-0"

    @Test func theFirstPlaceIsWrittenOnlyWhenNoPlaceIsStored() {
        let defaults = MemoryDefaults()
        #expect(MenuBarIconPlace.key == key)

        // The first start: no place is stored, so the app writes 420 points from the right edge.
        MenuBarIconPlace.writeFirstPosition(to: defaults)
        #expect(defaults.object(forKey: key) as? Double == 420)

        // The user moved the icon, and macOS stored the new place. A later start keeps it.
        defaults.set(137.5, forKey: key)
        MenuBarIconPlace.writeFirstPosition(to: defaults)
        #expect(defaults.object(forKey: key) as? Double == 137.5)
    }
}
