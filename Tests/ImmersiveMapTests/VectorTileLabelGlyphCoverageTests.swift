// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class VectorTileLabelGlyphCoverageTests: XCTestCase {
    func testCoverageAllowsOnlyGlyphsPresentInAtlas() {
        let coverage = VectorTileLabelGlyphCoverage(supportedScalars: [65, 66, 32])

        XCTAssertTrue(coverage.canRender("A B"))
        XCTAssertFalse(coverage.canRender("AC"))
    }

    func testExplicitCoverageAllowsLayoutControlsOutsideGlyphSet() {
        let coverage = VectorTileLabelGlyphCoverage(supportedScalars: [65])

        XCTAssertTrue(coverage.canRender("A\nA"))
        XCTAssertTrue(coverage.canRender("A\tA"))
        XCTAssertTrue(coverage.canRender("A\rA"))
    }

    func testCoverageCombinesBoldAndThinAtlasGlyphs() {
        let bold = AtlasData.testAtlas(glyphs: [65])
        let thin = AtlasData.testAtlas(glyphs: [66])

        let coverage = VectorTileLabelGlyphCoverage(atlasData: bold, thinAtlasData: thin)

        XCTAssertTrue(coverage.canRender("AB"))
        XCTAssertFalse(coverage.canRender("ABC"))
    }

    func testAtlasCoverageAllowsLayoutControlsOutsideGlyphSet() {
        let bold = AtlasData.testAtlas(glyphs: [65])
        let thin = AtlasData.testAtlas(glyphs: [])

        let coverage = VectorTileLabelGlyphCoverage(atlasData: bold, thinAtlasData: thin)

        XCTAssertTrue(coverage.canRender("A A\nA\rA\tA"))
    }

    func testAtlasCoverageRejectsUnsupportedNonWhitespaceScalar() {
        let bold = AtlasData.testAtlas(glyphs: [65])
        let thin = AtlasData.testAtlas(glyphs: [])

        let coverage = VectorTileLabelGlyphCoverage(atlasData: bold, thinAtlasData: thin)

        XCTAssertFalse(coverage.canRender("AЖA"))
    }

    func testCurrentAtlasRejectsUnsupportedJapaneseText() {
        XCTAssertFalse(VectorTileLabelGlyphCoverage.currentAtlas.canRender("東京"))
    }
}

private extension AtlasData {
    static func testAtlas(glyphs unicodes: [UInt32]) -> AtlasData {
        AtlasData(
            atlas: AtlasInfo(type: "msdf",
                             distanceRange: 8,
                             distanceRangeMiddle: 0,
                             size: 64,
                             width: 64,
                             height: 64,
                             yOrigin: "bottom"),
            metrics: Metrics(emSize: 1,
                             lineHeight: 1,
                             ascender: 1,
                             descender: 0,
                             underlineY: 0,
                             underlineThickness: 0),
            glyphs: unicodes.map { Glyph(unicode: $0, advance: 1, planeBounds: nil, atlasBounds: nil) }
        )
    }
}
