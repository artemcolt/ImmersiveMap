// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class VectorTileLabelDecisionEngineTests: XCTestCase {
    func testRussianPreferencesPreferRussianThenNativeThenEnglish() {
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Москва"),
            "name_en": stringValue("Moscow"),
            "name_ru": stringValue("Москва")
        ]
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let preferences = VectorTileLabelLanguagePreferences.from(settingsLanguage: .russian)

        XCTAssertEqual(preferences.selectedLanguage, .russian)
        XCTAssertEqual(resolver.resolveText(properties: properties, preferences: preferences), "Москва")
    }

    func testRussianPreferencesFallBackToNativeCyrillicWhenRussianNameIsAbsent() {
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Москва"),
            "name_en": stringValue("Moscow")
        ]
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let preferences = VectorTileLabelLanguagePreferences.from(settingsLanguage: .russian)

        XCTAssertEqual(resolver.resolveText(properties: properties, preferences: preferences), "Москва")
    }

    func testRussianPreferencesFallBackToEnglishWhenNativeNameIsNotRussianCompatible() {
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Moscow"),
            "name_en": stringValue("Moscow")
        ]
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let preferences = VectorTileLabelLanguagePreferences.from(settingsLanguage: .russian)

        XCTAssertEqual(resolver.resolveText(properties: properties, preferences: preferences), "Moscow")
    }

    func testEnglishPreferencesPreferEnglishThenNativeThenRussian() {
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Москва"),
            "name_en": stringValue("Moscow"),
            "name_ru": stringValue("Москва")
        ]
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let preferences = VectorTileLabelLanguagePreferences.from(settingsLanguage: .english)

        XCTAssertEqual(preferences.selectedLanguage, .english)
        XCTAssertEqual(resolver.resolveText(properties: properties, preferences: preferences), "Moscow")
    }

    func testEnglishPreferencesFallBackToNativeLatinWhenEnglishNameIsAbsent() {
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Moscow"),
            "name_ru": stringValue("Москва")
        ]
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let preferences = VectorTileLabelLanguagePreferences.from(settingsLanguage: .english)

        XCTAssertEqual(resolver.resolveText(properties: properties, preferences: preferences), "Moscow")
    }

    func testEnglishPreferencesFallBackToRussianWhenNativeNameIsNotEnglishCompatible() {
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Москва"),
            "name_ru": stringValue("Москва")
        ]
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let preferences = VectorTileLabelLanguagePreferences.from(settingsLanguage: .english)

        XCTAssertEqual(resolver.resolveText(properties: properties, preferences: preferences), "Москва")
    }

    func testUnsupportedGlyphCoverageRejectsText() {
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("東京")
        ]
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let preferences = VectorTileLabelLanguagePreferences.from(settingsLanguage: .english)

        XCTAssertNil(resolver.resolveText(properties: properties, preferences: preferences))
    }

    func testProviderFeatureIdentityParticipatesInCrossTileDeduplication() {
        let identity = VectorTileLabelIdentity.providerFeature(providerID: "mapbox",
                                                               layerName: "place_label",
                                                               featureID: 42)

        XCTAssertTrue(identity.participatesInCrossTileDeduplication)
        XCTAssertEqual(identity.runtimeKey, 17424410298459024603)
        XCTAssertEqual(identity.runtimeKey,
                       VectorTileLabelIdentity.providerFeature(providerID: "mapbox",
                                                               layerName: "place_label",
                                                               featureID: 42).runtimeKey)
    }

    func testSemanticIdentityUsesStableRuntimeKey() {
        let identity = VectorTileLabelIdentity.semantic(providerID: "mapbox",
                                                        kind: "place",
                                                        text: "Moscow",
                                                        worldBucket: SIMD2<Int32>(10, 20))

        XCTAssertTrue(identity.participatesInCrossTileDeduplication)
        XCTAssertEqual(identity.runtimeKey, 18093230200447490384)
    }

    func testTileLocalIdentityIncludesTileCoordinates() {
        let first = VectorTileLabelIdentity.tileLocal(tile: Tile(x: 10, y: 20, z: 5),
                                                      layerName: "poi_label",
                                                      text: "Museum",
                                                      anchor: SIMD2<Int16>(100, 200))
        let second = VectorTileLabelIdentity.tileLocal(tile: Tile(x: 11, y: 20, z: 5),
                                                       layerName: "poi_label",
                                                       text: "Museum",
                                                       anchor: SIMD2<Int16>(100, 200))

        XCTAssertFalse(first.participatesInCrossTileDeduplication)
        XCTAssertEqual(first.runtimeKey, 6949302229354522716)
        XCTAssertEqual(second.runtimeKey, 6830255165424541913)
        XCTAssertNotEqual(first.runtimeKey, second.runtimeKey)
    }

    private func stringValue(_ value: String) -> VectorTile_Tile.Value {
        var tileValue = VectorTile_Tile.Value()
        tileValue.stringValue = value
        return tileValue
    }
}
