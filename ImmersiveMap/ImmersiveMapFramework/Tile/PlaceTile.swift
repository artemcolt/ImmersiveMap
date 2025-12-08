//
//  PlaceTile.swift
//  ImmersiveMap
//
//  Created by Artem on 12/7/25.
//

struct PlaceTile: Hashable {
    let metalTile: MetalTile
    let placeIn: Tile
    let depth: UInt8
    
    func isReplacement() -> Bool {
        return metalTile.tile != placeIn
    }
}
