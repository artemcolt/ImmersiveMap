// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct TilePlacementPlanner {
    static func buildPlacements(targets: [VisibleTile],
                                readyTilesBySource: [Tile: MetalTile?],
                                zoom: Int,
                                previousZoom: Int,
                                previousContext: PlaceTilesContext) -> PlaceTilesContext {
        var placeTiles: [PlaceTile] = []

        for target in targets {
            let sourceTile = target.tile
            let lodKind: TileLodKind = sourceTile.z < zoom ? .coarseSubstitute : .exact
            let metalTile = readyTilesBySource[sourceTile] ?? nil

            func findFullReplacement() -> Bool {
                var bestReplacement: PlaceTile?
                for prev in previousContext.tilePlacements {
                    let prevSourceTile = prev.metalTile.tile

                    // Previous tile fully covers the required tile
                    // (including exact same tile identity).
                    if prevSourceTile == target.tile || prevSourceTile.covers(target.tile) {
                        if let currentBest = bestReplacement {
                            let currentBestTile = currentBest.metalTile.tile
                            // Keep the most detailed fallback source among
                            // all covering tiles from the previous frame.
                            if prevSourceTile.z > currentBestTile.z {
                                bestReplacement = prev
                            }
                        } else {
                            bestReplacement = prev
                        }
                    }
                }

                guard let bestReplacement else {
                    return false
                }

                placeTiles.append(PlaceTile(metalTile: bestReplacement.metalTile,
                                            placeIn: target,
                                            lodKind: .retainedReplacement))
                return true
            }

            func findPartialReplacement() -> Bool {
                var foundSome = false
                for prev in previousContext.tilePlacements {
                    let prevMetalTile = prev.metalTile
                    let prevSourceTile = prev.metalTile.tile

                    // Previous tile is inside the required tile
                    // (including exact same tile identity).
                    if prevSourceTile == target.tile || target.tile.covers(prevSourceTile) {
                        placeTiles.append(PlaceTile(metalTile: prevMetalTile,
                                                    placeIn: prev.placeIn,
                                                    lodKind: .retainedReplacement))
                        foundSome = true
                    }
                }
                return foundSome
            }

            // Replace missing tile with temporary tiles from the previous frame.
            if metalTile == nil {
                let zDiff = zoom - previousZoom

                if zDiff >= 0 {
                    if findFullReplacement() == false {
                        _ = findPartialReplacement()
                    }
                } else {
                    _ = findPartialReplacement()
                }

                continue
            }

            placeTiles.append(PlaceTile(metalTile: metalTile!,
                                        placeIn: target,
                                        lodKind: lodKind))
        }

        return PlaceTilesContext(tilePlacements: placeTiles)
    }
}
