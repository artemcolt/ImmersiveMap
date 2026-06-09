// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

enum GlobeTextureLayer: Int, Hashable {
    case base = 0
    case detail = 1
}

struct GlobeTexturePlaceTile: Hashable {
    let placeTile: PlaceTile
    let layer: GlobeTextureLayer

    var metalTile: MetalTile {
        placeTile.metalTile
    }

    var placeIn: VisibleTile {
        placeTile.placeIn
    }

    var lodKind: TileLodKind {
        placeTile.lodKind
    }
}

struct GlobeTexturePlaceTilesContext {
    let tilePlacements: [GlobeTexturePlaceTile]

    init(tilePlacements: [GlobeTexturePlaceTile]) {
        self.tilePlacements = tilePlacements
    }

    static let empty = GlobeTexturePlaceTilesContext(tilePlacements: [])
}
