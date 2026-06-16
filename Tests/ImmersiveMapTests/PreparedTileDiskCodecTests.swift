// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class PreparedTileDiskCodecTests: XCTestCase {
    func testPreparedTileCodecRoundTripsArbitraryLabelLanguageMetadata() throws {
        let tile = Tile(x: 1, y: 2, z: 3)
        let labelLanguage = ImmersiveMapSettings.LabelLanguage("pt-BR")
        let cacheIdentity = makeCacheIdentity(labelLanguage: labelLanguage)
        let preparedTile = makePreparedTile(tile: tile)

        let data = try PreparedTileDiskCodec.encode(preparedTile: preparedTile,
                                                    cacheIdentity: cacheIdentity)
        let decoded = try PreparedTileDiskCodec.decode(data: data,
                                                       expectedTile: tile,
                                                       cacheIdentity: cacheIdentity)

        XCTAssertEqual(decoded.tile, tile)
    }

    private func makeCacheIdentity(labelLanguage: ImmersiveMapSettings.LabelLanguage) -> PreparedTileCacheIdentity {
        PreparedTileCacheIdentity(preparedFormatVersion: PreparedTileDiskCaching.preparedFormatVersion,
                                  styleRevision: 1,
                                  tileSourceRevision: 2,
                                  flatSeparateRoadRenderingMinimumZoom: 3,
                                  textRevision: 4,
                                  labelLanguage: labelLanguage,
                                  houseNumbersEnabled: true,
                                  houseNumbersMinimumZoom: 15,
                                  capitalMaximumZoom: 12,
                                  cityMaximumZoom: 12,
                                  smallSettlementMaximumZoom: 12,
                                  landmarkMinimumZoom: 13,
                                  addTestBorders: false)
    }

    private func makePreparedTile(tile: Tile) -> PreparedTileCPU {
        let emptyGeometry = PreparedTileCPU.GeometryLayer(vertices: [],
                                                         indices: [],
                                                         styles: [],
                                                         overviewStyleMasks: [])
        let emptyRoadPhases = RoadGeometryPhases(shadow: emptyGeometry,
                                                 casing: emptyGeometry,
                                                 fill: emptyGeometry,
                                                 detail: emptyGeometry,
                                                 overlay: emptyGeometry)

        return PreparedTileCPU(tile: tile,
                               ground: emptyGeometry,
                               roads: RoadStructureBuckets(tunnel: emptyRoadPhases,
                                                          ground: emptyRoadPhases,
                                                          bridge: emptyRoadPhases),
                               bridgeOverlay: emptyGeometry,
                               extruded: PreparedTileCPU.Extruded(vertices: [],
                                                                  indices: [],
                                                                  styles: []),
                               textLabels: PreparedTileCPU.TextLabels(placementInputs: [],
                                                                       glyphRuns: [],
                                                                       poiIconRuns: []),
                               roadLabels: PreparedTileCPU.RoadLabels(pathInputs: [],
                                                                      pathRanges: [],
                                                                      pathLabels: [],
                                                                      labelStyle: nil,
                                                                      localGlyphVertices: [],
                                                                      glyphBounds: [],
                                                                      glyphBoundRanges: [],
                                                                      sizes: [],
                                                                      anchorRanges: [],
                                                                      anchors: []))
    }
}
