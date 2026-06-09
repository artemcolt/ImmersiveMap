// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct GlobeTexturePlacementPlanner {
    static func buildPlacements(baseTargets: [VisibleTile],
                                detailTargets: [VisibleTile],
                                readyTilesBySource: [Tile: MetalTile?],
                                baseZoom: Int,
                                previousBaseZoom: Int,
                                previousContext: GlobeTexturePlaceTilesContext) -> GlobeTexturePlaceTilesContext {
        let previousBaseContext = PlaceTilesContext(
            tilePlacements: previousContext.tilePlacements
                .filter { $0.layer == .base }
                .map(\.placeTile)
        )
        let baseContext = TilePlacementPlanner.buildPlacements(targets: baseTargets,
                                                               readyTilesBySource: readyTilesBySource,
                                                               zoom: baseZoom,
                                                               previousZoom: previousBaseZoom,
                                                               previousContext: previousBaseContext)
        let basePlacements = baseContext.tilePlacements.map {
            GlobeTexturePlaceTile(placeTile: $0, layer: .base)
        }
        let detailPlacements = detailTargets.compactMap { target -> GlobeTexturePlaceTile? in
            guard let metalTile = readyTilesBySource[target.tile] ?? nil else {
                return nil
            }
            let placeTile = PlaceTile(metalTile: metalTile,
                                      placeIn: target,
                                      lodKind: metalTile.tile == target.tile ? .exact : .coarseSubstitute)
            return GlobeTexturePlaceTile(placeTile: placeTile, layer: .detail)
        }

        return GlobeTexturePlaceTilesContext(tilePlacements: basePlacements + detailPlacements)
    }
}
