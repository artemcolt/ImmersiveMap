//
//  MetalTile.swift
//  TucikMap
//
//  Created by Artem on 6/6/25.
//

import MetalKit


class MetalTile: Hashable {
    static func == (lhs: MetalTile, rhs: MetalTile) -> Bool {
        return lhs.tile.x == rhs.tile.x && lhs.tile.z == rhs.tile.z && lhs.tile.y == rhs.tile.y
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(tile.x)
        hasher.combine(tile.y)
        hasher.combine(tile.z)
    }
    
    let tile            : Tile
    let tileBuffers     : TileBuffers
    
    
    init(
        tile: Tile,
        tileBuffers: TileBuffers,
    ) {
        self.tile = tile
        self.tileBuffers = tileBuffers
    }
}
