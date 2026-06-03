// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  PlaceTileTrackingState.swift
//  ImmersiveMap
//

struct PlaceTileTrackingState {
    static let empty = PlaceTileTrackingState(placeTiles: [])

    let placeTiles: [PlaceTile]

    init(placeTiles: [PlaceTile]) {
        self.placeTiles = placeTiles
    }
}
