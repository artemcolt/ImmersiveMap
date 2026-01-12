//
//  PlaceTilesContext.swift
//  ImmersiveMap
//
//  Created by Artem on 1/26/26.
//

struct PlaceTilesContext {
    let placeTiles: [PlaceTile]
    let placeTilesByTile: [Tile: PlaceTile]
    let visibleTiles: [Tile]
    let detailTiles: [Tile]

    init(placeTiles: [PlaceTile]) {
        self.placeTiles = placeTiles
        var byTile: [Tile: PlaceTile] = [:]
        byTile.reserveCapacity(placeTiles.count)
        for placeTile in placeTiles {
            byTile[placeTile.metalTile.tile] = placeTile
        }
        self.placeTilesByTile = byTile
        self.visibleTiles = placeTiles.map { $0.metalTile.tile }
        self.detailTiles = placeTiles
            .map { $0.metalTile.tile }
            .filter { $0.isCoarseTile == false }
    }

    static let empty = PlaceTilesContext(placeTiles: [])
}
