//
//  PlaceTile.swift
//  ImmersiveMapFramework
//  Created by Artem on 12/7/25.
//

struct PlaceTile: Hashable {
    let metalTile: MetalTile
    let placeIn: VisibleTile
    let lodKind: TileLodKind

    func isReplacement() -> Bool {
        return lodKind != .exact || metalTile.tile != placeIn.tile
    }
}
