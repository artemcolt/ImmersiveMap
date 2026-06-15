// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct GlobeTexturePlacementPlanner {
    static func buildPlacements(baseTargets: [VisibleTile],
                                readyTilesBySource: [Tile: MetalTile?],
                                baseZoom: Int,
                                previousBaseZoom: Int,
                                previousContext: GlobeTexturePlaceTilesContext) -> GlobeTexturePlaceTilesContext {
        let previousBaseContext = PlaceTilesContext(
            tilePlacements: previousContext.tilePlacements.map(\.placeTile)
        )
        let baseContext = TilePlacementPlanner.buildPlacements(targets: baseTargets,
                                                               readyTilesBySource: readyTilesBySource,
                                                               zoom: baseZoom,
                                                               previousZoom: previousBaseZoom,
                                                               previousContext: previousBaseContext)
        let basePlacements = baseContext.tilePlacements.map {
            GlobeTexturePlaceTile(placeTile: $0)
        }

        return GlobeTexturePlaceTilesContext(tilePlacements: basePlacements)
    }
}
