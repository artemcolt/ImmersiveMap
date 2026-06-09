// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  VisibleContentState.swift
//  ImmersiveMap
//

import simd

struct VisibleContentState {
    static let empty = VisibleContentState(centerWorldMercator: SIMD2<Double>(0.5, 0.5),
                                           center: Center(tileX: 0, tileY: 0),
                                           visibleTiles: [],
                                           tileZoomLevel: 0,
                                           globeDetailVisibleTiles: [],
                                           globeDetailTileZoomLevel: nil,
                                           coverageVersion: 0)

    let centerWorldMercator: SIMD2<Double>
    let center: Center
    let visibleTiles: [VisibleTile]
    let tileZoomLevel: Int
    let globeDetailVisibleTiles: [VisibleTile]
    let globeDetailTileZoomLevel: Int?
    let coverageVersion: UInt64
}
