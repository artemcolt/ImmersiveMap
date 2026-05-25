//
//  PlaceTileTrackingState.swift
//  ImmersiveMapFramework
//

struct PlaceTileTrackingState {
    static let empty = PlaceTileTrackingState(placeTiles: [])

    let placeTiles: [PlaceTile]

    init(placeTiles: [PlaceTile]) {
        self.placeTiles = placeTiles
    }
}
