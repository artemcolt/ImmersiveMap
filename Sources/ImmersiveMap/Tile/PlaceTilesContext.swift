//
//  PlaceTilesContext.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/26/26.
//

struct PlaceTilesContext {
    /// Logical tile layout for flat/extruded geometry rendering:
    /// carries GPU tile payload and placement target tile.
    let tilePlacements: [PlaceTile]
    
    init(tilePlacements: [PlaceTile]) {
        self.tilePlacements = tilePlacements
    }

    static let empty = PlaceTilesContext(tilePlacements: [])
}
