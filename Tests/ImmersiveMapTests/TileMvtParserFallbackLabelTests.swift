// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class TileMvtParserFallbackLabelTests: XCTestCase {
    func testFrenchPreferencesResolveRenderableFallbackWaterLabel() throws {
        let labels = try parseFallbackWaterLabels(language: .french)

        XCTAssertTrue(labels.contains("Ocean Atlantique"))
        XCTAssertFalse(labels.contains("Atlantic Ocean"))
    }

    func testGermanPreferencesResolveRenderableFallbackWaterLabel() throws {
        let labels = try parseFallbackWaterLabels(language: .german)

        XCTAssertTrue(labels.contains("Atlantischer Ozean"))
        XCTAssertFalse(labels.contains("Atlantic Ocean"))
    }

    func testSpanishPreferencesResolveRenderableFallbackWaterLabel() throws {
        let labels = try parseFallbackWaterLabels(language: .spanish)

        XCTAssertTrue(labels.contains("Oceano Atlantico"))
        XCTAssertFalse(labels.contains("Atlantic Ocean"))
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
        glyphCoverage: VectorTileLabelGlyphCoverage = .legacyAtlasForTests
    ) throws -> [String] {
        var config = ImmersiveMapSettings.default
        config.labels.language = language

        let parser = TileMvtParser(determineFeatureStyle: DetermineFeatureStyle(mapStyle: FallbackWaterLabelStyle()),
                                   config: config,
                                   glyphCoverage: glyphCoverage)
        let parsedTile = try parser.parse(tile: Tile(x: 0, y: 0, z: 0),
                                          mvtData: try VectorTile_Tile().serializedData())

        return parsedTile.textLabels.map(\.text)
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
