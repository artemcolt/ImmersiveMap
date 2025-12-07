//
//  PlaceTile.swift
//  ImmersiveMap
//
//  Created by Artem on 12/7/25.
//

struct PlaceTile {
    let metalTile: MetalTile
    let placeIn: Tile
    
    func isReplacement() -> Bool {
        return metalTile.tile != placeIn
    }
}
