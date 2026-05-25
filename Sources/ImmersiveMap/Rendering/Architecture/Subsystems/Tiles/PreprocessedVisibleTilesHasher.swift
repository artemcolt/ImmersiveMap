//
//  PreprocessedVisibleTilesHasher.swift
//  ImmersiveMapFramework
//

import Foundation

enum PreprocessedVisibleTilesHasher {
    static func computePreprocessedVisibleTilesHash(
        preprocessedVisibleTiles: [VisibleTile],
        readyTilesBySource: [Tile: MetalTile?]
    ) -> Int {
        computePreprocessedVisibleTilesHash(preprocessedVisibleTiles: preprocessedVisibleTiles) { source in
            if let sourceTile = readyTilesBySource[source] {
                return sourceTile != nil
            }
            return false
        }
    }

    static func computePreprocessedVisibleTilesHash(
        preprocessedVisibleTiles: [VisibleTile],
        isSourceReady: (Tile) -> Bool
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(preprocessedVisibleTiles.count)
        for preprocessedVisibleTile in preprocessedVisibleTiles {
            hasher.combine(preprocessedVisibleTile)
            hasher.combine(isSourceReady(preprocessedVisibleTile.tile))
        }
        return hasher.finalize()
    }
}
