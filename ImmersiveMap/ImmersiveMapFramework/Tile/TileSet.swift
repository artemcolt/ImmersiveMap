//
//  TileSet.swift
//  ImmersiveMap
//
//  Created by Artem on 12/7/25.
//

class TileSet {
    private var tiles: Set<Tile> = []
    private var cachedHash: Int = 0
    
    var hashValue: Int {
        return cachedHash
    }
    
    func update(with newTiles: [Tile]) -> Bool {
        let newSet = Set(newTiles)
        
        guard newSet != tiles else { return false }
        
        tiles = newSet
        cachedHash = newSet.hashValue
        return true
    }
}
