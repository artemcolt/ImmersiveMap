// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class NightLightsGlobeTextureSubsystemTests: XCTestCase {
    func testRequiredNightLightTilesDeduplicatesMappedTilesAndSortsByZoomYThenX() {
        let tileSet = makeTileSet()
        let visibleTiles = [
            Tile(x: 104, y: 140, z: 8),
            Tile(x: 101, y: 140, z: 8),
            Tile(x: 100, y: 140, z: 8)
        ]

        let requiredTiles = NightLightsGlobeTextureSubsystem.requiredNightLightTiles(for: visibleTiles,
                                                                                     tileSet: tileSet)

        XCTAssertEqual(requiredTiles, [
            Tile(x: 25, y: 35, z: 6),
            Tile(x: 26, y: 35, z: 6)
        ])
    }

    func testRequiredNightLightTilesSortsByZoomThenYThenX() {
        let tileSet = makeTileSet()
        let visibleTiles = [
            Tile(x: 9, y: 2, z: 6),
            Tile(x: 8, y: 2, z: 5),
            Tile(x: 7, y: 1, z: 5),
            Tile(x: 9, y: 9, z: 4),
            Tile(x: 3, y: 2, z: 6),
            Tile(x: 3, y: 2, z: 6)
        ]

        let requiredTiles = NightLightsGlobeTextureSubsystem.requiredNightLightTiles(for: visibleTiles,
                                                                                     tileSet: tileSet)

        XCTAssertEqual(requiredTiles, [
            Tile(x: 9, y: 9, z: 4),
            Tile(x: 7, y: 1, z: 5),
            Tile(x: 8, y: 2, z: 5),
            Tile(x: 3, y: 2, z: 6),
            Tile(x: 9, y: 2, z: 6)
        ])
    }

    func testRequiredNightLightTilesDropsVisibleTilesBelowMinimumZoom() {
        let tileSet = makeTileSet()

        let requiredTiles = NightLightsGlobeTextureSubsystem.requiredNightLightTiles(for: [
            Tile(x: 1, y: 1, z: 2),
            Tile(x: 4, y: 4, z: 4)
        ], tileSet: tileSet)

        XCTAssertEqual(requiredTiles, [
            Tile(x: 4, y: 4, z: 4)
        ])
    }

    func testRenderableRequiredNightLightTilesDeduplicatesInVisibleTileOrder() {
        let tileSet = makeTileSet()

        let requiredTiles = NightLightsGlobeTextureSubsystem.renderableRequiredNightLightTiles(for: [
            Tile(x: 40, y: 44, z: 8),
            Tile(x: 41, y: 44, z: 8),
            Tile(x: 4, y: 4, z: 4),
            Tile(x: 8, y: 2, z: 5)
        ], tileSet: tileSet)

        XCTAssertEqual(requiredTiles, [
            Tile(x: 10, y: 11, z: 6),
            Tile(x: 4, y: 4, z: 4),
            Tile(x: 8, y: 2, z: 5)
        ])
    }

    func testRenderableRequiredNightLightTilesCapsToShaderEntryBudget() {
        let tileSet = makeTileSet()
        let visibleTiles = (0..<(NightLightsAtlasSurfaceBinding.maxEntryCount + 12)).map { index in
            Tile(x: index % 64, y: index / 64, z: 6)
        }

        let requiredTiles = NightLightsGlobeTextureSubsystem.renderableRequiredNightLightTiles(for: visibleTiles,
                                                                                               tileSet: tileSet)

        XCTAssertEqual(requiredTiles.count, NightLightsAtlasSurfaceBinding.maxEntryCount)
        XCTAssertEqual(requiredTiles.first, Tile(x: 0, y: 0, z: 6))
        XCTAssertEqual(requiredTiles.last, Tile(x: 63, y: 1, z: 6))
    }

    private func makeTileSet() -> NightLightsTileSet {
        NightLightsTileSet(metadata: NightLightsTileSet.Metadata(version: 1,
                                                                 format: "jpg",
                                                                 tileSize: 1024,
                                                                 minZoom: 4,
                                                                 maxZoom: 6,
                                                                 source: "NASA Black Marble 2016",
                                                                 attribution: "NASA Earth Observatory"))
    }
}
