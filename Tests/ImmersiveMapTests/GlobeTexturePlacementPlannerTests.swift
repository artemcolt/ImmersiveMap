// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import MetalKit
import XCTest

final class GlobeTexturePlacementPlannerTests: XCTestCase {
    func testBuildPlacementsKeepsBaseAndDetailInSeparateLayers() throws {
        let baseTile = Tile(x: 1, y: 1, z: 1)
        let detailTile = Tile(x: 5, y: 4, z: 3)
        let baseMetalTile = MetalTile(tile: baseTile, tileBuffers: try makeTileBuffers())
        let detailMetalTile = MetalTile(tile: detailTile, tileBuffers: try makeTileBuffers())

        let context = GlobeTexturePlacementPlanner.buildPlacements(
            baseTargets: [VisibleTile(tile: baseTile)],
            detailTargets: [VisibleTile(tile: detailTile)],
            readyTilesBySource: [
                baseTile: baseMetalTile,
                detailTile: detailMetalTile
            ],
            baseZoom: 1,
            previousBaseZoom: 1,
            previousContext: .empty
        )

        XCTAssertEqual(context.tilePlacements.map(\.layer), [.base, .detail])
        XCTAssertEqual(context.tilePlacements.map(\.placeIn.tile), [baseTile, detailTile])
    }

    func testBuildPlacementsSkipsMissingDetailWithoutRemovingBaseCoverage() throws {
        let baseTile = Tile(x: 1, y: 1, z: 1)
        let detailTile = Tile(x: 5, y: 4, z: 3)
        let baseMetalTile = MetalTile(tile: baseTile, tileBuffers: try makeTileBuffers())

        let context = GlobeTexturePlacementPlanner.buildPlacements(
            baseTargets: [VisibleTile(tile: baseTile)],
            detailTargets: [VisibleTile(tile: detailTile)],
            readyTilesBySource: [
                baseTile: baseMetalTile,
                detailTile: nil
            ],
            baseZoom: 1,
            previousBaseZoom: 1,
            previousContext: .empty
        )

        XCTAssertEqual(context.tilePlacements.count, 1)
        XCTAssertEqual(context.tilePlacements.first?.layer, .base)
        XCTAssertEqual(context.tilePlacements.first?.placeIn.tile, baseTile)
    }

    private func makeTileBuffers() throws -> TileBuffers {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is required for MetalTile test fixture.")
        }
        let value: UInt32 = 0
        let buffer = device.makeBuffer(bytes: [value], length: MemoryLayout<UInt32>.stride)!
        let ground = TileBuffers.GeometryLayer(verticesBuffer: buffer,
                                               indicesBuffer: buffer,
                                               stylesBuffer: buffer,
                                               overviewStyleMaskBuffer: buffer,
                                               indicesCount: 0,
                                               verticesCount: 0)
        let extruded = TileBuffers.Extruded(verticesBuffer: buffer,
                                            indicesBuffer: buffer,
                                            stylesBuffer: buffer,
                                            indicesCount: 0,
                                            verticesCount: 0)
        let phases = RoadGeometryPhases(shadow: ground,
                                        casing: ground,
                                        fill: ground,
                                        detail: ground,
                                        overlay: ground)
        let roads = RoadStructureBuckets(tunnel: phases,
                                         ground: phases,
                                         bridge: phases)
        return TileBuffers(ground: ground,
                           roads: roads,
                           bridgeOverlay: ground,
                           extruded: extruded,
                           textLabels: TileBuffers.TextLabels(placementInputs: [],
                                                               labelsByStyleRuns: [],
                                                               poiIconRuns: []),
                           roadLabels: TileBuffers.RoadLabels(pathInputs: [],
                                                              pathRanges: [],
                                                              pathLabels: [],
                                                              labelStyle: nil,
                                                              localGlyphVerticesBuffer: nil,
                                                              localGlyphVertexCount: 0,
                                                              glyphBounds: [],
                                                              glyphBoundRanges: [],
                                                              sizes: [],
                                                              anchorRanges: [],
                                                              anchors: []))
    }
}
