import SwiftUI
import XCTest
@testable import KroChat

@MainActor
final class ThemeStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "krochat.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDuplicateCreatesCustomAndSelectsIt() throws {
        let store = ThemeStore(defaults: makeDefaults())
        let copy = try XCTUnwrap(store.duplicate(KroTheme.presets[0]))
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertEqual(store.selectedID, copy.id)
        XCTAssertEqual(store.customThemes.count, 1)
    }

    func testBuiltInThemesAreNotEditable() {
        let store = ThemeStore(defaults: makeDefaults())
        var preset = KroTheme.presets[0]
        preset.name = "Hacked"
        store.update(preset)
        XCTAssertEqual(store.all.first?.name, "Ocean")
    }

    func testExportImportRoundTripAssignsNewID() throws {
        let store = ThemeStore(defaults: makeDefaults())
        let json = store.exportJSON(for: KroTheme.presets[1])
        XCTAssertFalse(json.isEmpty)
        let added = try store.importJSON(json)
        XCTAssertEqual(added, 1)
        XCTAssertNotEqual(store.customThemes[0].id, KroTheme.presets[1].id)
        XCTAssertFalse(store.customThemes[0].isBuiltIn)
    }

    func testImportRejectsGarbageAndBadColors() {
        let store = ThemeStore(defaults: makeDefaults())
        XCTAssertThrowsError(try store.importJSON("not json"))
        let bad = KroTheme(name: "Bad", accentHex: "ZZZZZZ")
        let json = store.exportJSON(for: bad)
        XCTAssertThrowsError(try store.importJSON(json))
        XCTAssertTrue(store.customThemes.isEmpty)
    }

    func testPersistenceAcrossInstances() throws {
        let defaults = makeDefaults()
        let first = ThemeStore(defaults: defaults)
        let copy = try XCTUnwrap(first.duplicate(KroTheme.presets[2]))
        let second = ThemeStore(defaults: defaults)
        XCTAssertEqual(second.selectedID, copy.id)
        XCTAssertEqual(second.customThemes.count, 1)
    }

    func testHexRoundTrip() {
        XCTAssertEqual(Color(hex: "2F6BFF").toHex(), "2F6BFF")
        XCTAssertTrue(ThemeStore.isValidHex("12806A"))
        XCTAssertFalse(ThemeStore.isValidHex("12806"))
    }
}
