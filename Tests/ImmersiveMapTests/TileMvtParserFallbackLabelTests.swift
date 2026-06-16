// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class TileMvtParserFallbackLabelTests: XCTestCase {
    func testFrenchPreferencesFallBackToEnglishWhenAccentedFallbackWaterLabelIsUnsupported() throws {
        let labels = try parseFallbackWaterLabels(language: .french)

        XCTAssertTrue(labels.contains("Atlantic Ocean"))
        XCTAssertFalse(labels.contains("Océan Atlantique"))
    }

    func testGermanPreferencesResolveRenderableFallbackWaterLabel() throws {
        let labels = try parseFallbackWaterLabels(language: .german)

        XCTAssertTrue(labels.contains("Atlantischer Ozean"))
        XCTAssertFalse(labels.contains("Atlantic Ocean"))
    }

    func testSpanishPreferencesFallBackToEnglishWhenAccentedFallbackWaterLabelIsUnsupported() throws {
        let labels = try parseFallbackWaterLabels(language: .spanish)

        XCTAssertTrue(labels.contains("Atlantic Ocean"))
        XCTAssertFalse(labels.contains("Océano Atlántico"))
    }

    func testSpanishSeaFallbackFallsBackToEnglishWhenAccentedLabelIsUnsupportedAtZoomTwo() throws {
        let labels = try parseFallbackWaterLabels(language: .spanish,
                                                  tile: Tile(x: 2, y: 1, z: 2))

        XCTAssertTrue(labels.contains("Mediterranean Sea"))
        XCTAssertFalse(labels.contains("Mar Mediterráneo"))
    }

    func testExistingProviderWaterAliasSuppressesLocalizedFallbackDuplicate() throws {
        let labels = try parseFallbackWaterLabels(language: .russian,
                                                  tile: Tile(x: 0, y: 0, z: 0),
                                                  mvtData: try makeProviderAtlanticOceanTile().serializedData())

        XCTAssertEqual(labels.filter { $0 == "Atlantic Ocean" }.count, 1)
        XCTAssertFalse(labels.contains("Атлантический океан"))
    }

    func testPreferredFallbackWaterLabelWithUnsupportedGlyphsFallsBackToEnglish() throws {
        let asciiOnlyCoverage = VectorTileLabelGlyphCoverage(
            supportedScalars: Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ".unicodeScalars.map(\.value))
        )
        let labels = try parseFallbackWaterLabels(language: .russian,
                                                  glyphCoverage: asciiOnlyCoverage)

        XCTAssertTrue(labels.contains("Atlantic Ocean"))
        XCTAssertFalse(labels.contains("Атлантический океан"))
    }

    func testEnglishAndRussianFallbackWaterLabelsRemainAvailable() throws {
        let englishLabels = try parseFallbackWaterLabels(language: .english)
        let russianLabels = try parseFallbackWaterLabels(language: .russian)

        XCTAssertTrue(englishLabels.contains("Atlantic Ocean"))
        XCTAssertTrue(russianLabels.contains("Атлантический океан"))
    }

    private func parseFallbackWaterLabels(
        language: ImmersiveMapSettings.LabelLanguage,
        tile: Tile = Tile(x: 0, y: 0, z: 0),
        mvtData: Data? = nil,
        glyphCoverage: VectorTileLabelGlyphCoverage = .legacyAtlasForTests
    ) throws -> [String] {
        var config = ImmersiveMapSettings.default
        config.labels.language = language

        let parser = TileMvtParser(determineFeatureStyle: DetermineFeatureStyle(mapStyle: FallbackWaterLabelStyle()),
                                   config: config,
                                   glyphCoverage: glyphCoverage)
        let parsedTile = try parser.parse(tile: tile,
                                          mvtData: mvtData ?? VectorTile_Tile().serializedData())

        return parsedTile.textLabels.map(\.text)
    }

    private func makeProviderAtlanticOceanTile() -> VectorTile_Tile {
        var feature = VectorTile_Tile.Feature()
        feature.id = 1
        feature.type = .point
        feature.tags = [
            0, 0,
            1, 1,
            2, 2,
            3, 2
        ]
        feature.geometry = [
            command(id: 1, count: 1),
            parameter(2048),
            parameter(2048)
        ]

        var layer = VectorTile_Tile.Layer()
        layer.version = 2
        layer.name = "natural_label"
        layer.extent = 4096
        layer.keys = ["class", "type", "name", "name_en"]
        layer.values = [
            stringValue("ocean"),
            stringValue("ocean"),
            stringValue("Atlantic Ocean")
        ]
        layer.features = [feature]

        var tile = VectorTile_Tile()
        tile.layers = [layer]
        return tile
    }

    private func command(id: UInt32, count: UInt32) -> UInt32 {
        (count << 3) | id
    }

    private func parameter(_ value: Int32) -> UInt32 {
        UInt32(bitPattern: (value << 1) ^ (value >> 31))
    }

    private func stringValue(_ value: String) -> VectorTile_Tile.Value {
        var tileValue = VectorTile_Tile.Value()
        tileValue.stringValue = value
        return tileValue
    }
}

private final class FallbackWaterLabelStyle: ImmersiveMapStyle {
    let preparedTileStyleRevision: UInt32 = 1

    private let oceanLabelTextStyle = LabelTextStyle(key: 3,
                                                     fillColor: SIMD3<Float>(0, 0, 1),
                                                     strokeColor: SIMD3<Float>(1, 1, 1),
                                                     strokeWidthPx: 1,
                                                     sizePx: 12,
                                                     weight: .bold)
    private let seaLabelTextStyle = LabelTextStyle(key: 4,
                                                   fillColor: SIMD3<Float>(0, 0, 1),
                                                   strokeColor: SIMD3<Float>(1, 1, 1),
                                                   strokeWidthPx: 1,
                                                   sizePx: 10,
                                                   weight: .thin)

    func getMapBaseColors() -> ImmersiveMapBaseColors {
        ImmersiveMapBaseColors()
    }

    func makeStyle(data: DetFeatureStyleData) -> FeatureStyle {
        let labelTextStyle: LabelTextStyle?
        switch data.properties["class"]?.stringValue {
        case "ocean":
            labelTextStyle = oceanLabelTextStyle
        case "sea":
            labelTextStyle = seaLabelTextStyle
        default:
            labelTextStyle = nil
        }

        return FeatureStyle(key: UInt8(labelTextStyle?.key ?? 0),
                            color: SIMD4<Float>(1, 1, 1, 1),
                            parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 1),
                            labelTextStyle: labelTextStyle)
    }
}
