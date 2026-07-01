// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import MetalKit
import XCTest

final class TilePlacementPlannerTests: XCTestCase {
    func testBuildPlacementsUsesCurrentReadyParentForMissingTile() throws {
        let parentTile = Tile(x: 8, y: 5, z: 4)
        let targetTile = Tile(x: 34, y: 22, z: 6)
        let target = VisibleTile(tile: targetTile)
        let parentMetalTile = MetalTile(tile: parentTile, tileBuffers: try makeTileBuffers())

        let context = TilePlacementPlanner.buildPlacements(
            targets: [target],
            readyTilesBySource: [
                targetTile: nil,
                parentTile: parentMetalTile
            ],
            zoom: 6,
            previousZoom: 6,
            previousContext: .empty
        )

        XCTAssertEqual(context.tilePlacements.count, 1)
        guard let placement = context.tilePlacements.first else {
            return
        }
        XCTAssertEqual(placement.metalTile.tile, parentTile)
        XCTAssertEqual(placement.placeIn.tile, targetTile)
        XCTAssertEqual(placement.lodKind, .retainedReplacement)
    }

    func testBuildPlacementsPrefersMostDetailedCurrentReadyParent() throws {
        let coarseParentTile = Tile(x: 4, y: 2, z: 3)
        let detailedParentTile = Tile(x: 8, y: 5, z: 4)
        let targetTile = Tile(x: 34, y: 22, z: 6)
        let target = VisibleTile(tile: targetTile)
        let coarseParentMetalTile = MetalTile(tile: coarseParentTile, tileBuffers: try makeTileBuffers())
        let detailedParentMetalTile = MetalTile(tile: detailedParentTile, tileBuffers: try makeTileBuffers())

        let context = TilePlacementPlanner.buildPlacements(
            targets: [target],
            readyTilesBySource: [
                targetTile: nil,
                coarseParentTile: coarseParentMetalTile,
                detailedParentTile: detailedParentMetalTile
            ],
            zoom: 6,
            previousZoom: 6,
            previousContext: .empty
        )

        XCTAssertEqual(context.tilePlacements.count, 1)
        guard let placement = context.tilePlacements.first else {
            return
        }
        XCTAssertEqual(placement.metalTile.tile, detailedParentTile)
        XCTAssertEqual(placement.placeIn.tile, targetTile)
        XCTAssertEqual(placement.lodKind, .retainedReplacement)
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
                           textLabels: TileBuffers.TextLabels(full: emptyTextLabelSet(),
                                                               reduced: emptyTextLabelSet(),
                                                               minimal: emptyTextLabelSet()),
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

    private func emptyTextLabelSet() -> TileBuffers.TextLabelSet {
        TileBuffers.TextLabelSet(placementInputs: [],
                                 labelsByStyleRuns: [],
                                 poiIconRuns: [])
    }
}
