import SwiftUI
import XCTest
@testable import KroGram

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

    func testEffectsDefaultToFullAndRespectMotionAccessibility() {
        let store = ThemeStore(defaults: makeDefaults())
        XCTAssertEqual(store.effects, .full)
        XCTAssertFalse(store.shouldAnimate(reduceMotion: true))
        XCTAssertEqual(store.effectiveEffects(reduceMotion: true), .balanced)

        store.effects = .off
        XCTAssertEqual(store.effectiveEffects(reduceMotion: false), .off)
        XCTAssertFalse(store.shouldAnimate(reduceMotion: false))
    }

    func testHexRoundTrip() {
        XCTAssertEqual(Color(hex: "2F6BFF").toHex(), "2F6BFF")
        XCTAssertTrue(ThemeStore.isValidHex("12806A"))
        XCTAssertFalse(ThemeStore.isValidHex("12806"))
    }

    func testLegacyThemeDecodingMigratesWallpaperAndDefaultsNewFields() throws {
        let data = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000010",
              "name": "Legacy",
              "accentHex": "12806A",
              "bubbleRadius": 20,
              "fontChoice": "rounded",
              "fontScale": 1,
              "density": "regular",
              "wallpaper": "dots",
              "isBuiltIn": false
            }
            """.utf8
        )

        let theme = try JSONDecoder().decode(KroTheme.self, from: data)

        XCTAssertEqual(theme.schemaVersion, KroTheme.currentSchemaVersion)
        XCTAssertEqual(theme.background.kind, .pattern)
        XCTAssertEqual(theme.background.pattern, .dots)
        XCTAssertEqual(theme.neon, NeonConfiguration())
    }

    func testThemeStoreMigratesAndPersistsLegacyCustomThemes() throws {
        let defaults = makeDefaults()
        let legacy = Data(
            """
            [{
              "id": "00000000-0000-0000-0000-000000000011",
              "name": "Legacy",
              "accentHex": "12806A",
              "wallpaper": "plain"
            }]
            """.utf8
        )
        defaults.set(legacy, forKey: "krochat.themes.custom.v1")

        let store = ThemeStore(defaults: defaults)

        XCTAssertEqual(store.customThemes.count, 1)
        XCTAssertEqual(store.customThemes[0].background.kind, .solid)
        let saved = try XCTUnwrap(defaults.data(forKey: "krochat.themes.custom.v1"))
        let reloaded = try JSONDecoder().decode([KroTheme].self, from: saved)
        XCTAssertEqual(reloaded[0].schemaVersion, KroTheme.currentSchemaVersion)
    }

    func testBackgroundAndNeonConfigurationsClampUnsafeValues() {
        var background = BackgroundConfiguration(
            auroraBlobCount: 99,
            auroraSpeed: 4,
            meshPoints: [MeshColorPoint(x: 2, y: -1, hex: "invalid")],
            patternOpacity: 2,
            photoScale: 0.1,
            photoBlur: 500
        )
        background.gradientHexes = ["not-a-color"]
        let safeBackground = background.validated()

        XCTAssertEqual(safeBackground.auroraBlobCount, 8)
        XCTAssertEqual(safeBackground.auroraSpeed, 1)
        XCTAssertEqual(safeBackground.meshPoints[0].x, 1)
        XCTAssertEqual(safeBackground.meshPoints[0].y, 0)
        XCTAssertEqual(safeBackground.patternOpacity, 0.5)
        XCTAssertEqual(safeBackground.photoScale, 1)
        XCTAssertEqual(safeBackground.photoBlur, 100)
        XCTAssertEqual(safeBackground.gradientHexes.count, 2)

        var neon = NeonElementStyle(intensity: 2, glowRadius: 100, layers: 0, pulseAmplitude: 1)
        neon.borderWidth = 10
        let safeNeon = neon.validated()
        XCTAssertEqual(safeNeon.intensity, 1)
        XCTAssertEqual(safeNeon.glowRadius, 32)
        XCTAssertEqual(safeNeon.layers, 1)
        XCTAssertEqual(safeNeon.pulseAmplitude, 0.3)
        XCTAssertEqual(safeNeon.borderWidth, 4)
    }

    func testBackgroundPresetsAreCodeDrawnAndUnique() {
        XCTAssertGreaterThanOrEqual(BackgroundPreset.allCases.count, 10)
        let backgrounds = BackgroundPreset.allCases.map(\.configuration)
        XCTAssertEqual(Set(BackgroundPreset.allCases.map(\.rawValue)).count, backgrounds.count)
        XCTAssertTrue(backgrounds.allSatisfy { $0.validated() == $0 })
    }

    func testExportOmitsLocalPhotoReferenceAndImportsVersionOneBundle() throws {
        let store = ThemeStore(defaults: makeDefaults())
        var theme = KroTheme(name: "Photo", accentHex: "2F6BFF")
        theme.background.photoID = UUID()

        let json = store.exportJSON(for: theme)

        XCTAssertFalse(json.contains("photoID"))
        XCTAssertEqual(try store.importJSON(json), 1)
        XCTAssertNil(store.customThemes[0].background.photoID)

        let legacyBundle = """
        {"format":"krochat-theme","version":1,"themes":[
          {"name":"V1","accentHex":"2F6BFF","wallpaper":"gradient"}
        ]}
        """
        XCTAssertEqual(try store.importJSON(legacyBundle), 1)
    }
}
