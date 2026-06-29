// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class NightLightsGlobeTextureSubsystem: RenderSubsystem {
    let name: String = "NightLights"

    private let tileSetStore: NightLightsTileSetStore
    private let tileCache: NightLightsTileCache
    private let atlasTexture: NightLightsAtlasTexture

    private var previousRequiredTiles: [Tile]?
    private var previousReadyTiles: [Tile]?
    private var atlasState: NightLightsAtlasState = .empty

    init(tileSetStore: NightLightsTileSetStore,
         tileCache: NightLightsTileCache,
         atlasTexture: NightLightsAtlasTexture) {
        self.tileSetStore = tileSetStore
        self.tileCache = tileCache
        self.atlasTexture = atlasTexture
    }

    static func requiredNightLightTiles(for visibleTiles: [Tile],
                                        tileSet: NightLightsTileSet) -> [Tile] {
        let mappedTiles = visibleTiles.compactMap { tileSet.mapping(for: $0)?.tile }
        return Array(Set(mappedTiles)).sorted {
            if $0.z != $1.z {
                return $0.z < $1.z
            }
            if $0.y != $1.y {
                return $0.y < $1.y
            }
            return $0.x < $1.x
        }
    }

    static func renderableRequiredNightLightTiles(for visibleTiles: [Tile],
                                                  tileSet: NightLightsTileSet) -> [Tile] {
        var seenTiles = Set<Tile>()
        var requiredTiles: [Tile] = []
        requiredTiles.reserveCapacity(min(visibleTiles.count,
                                          NightLightsAtlasSurfaceBinding.maxEntryCount))

        for visibleTile in visibleTiles {
            guard let tile = tileSet.mapping(for: visibleTile)?.tile,
                  seenTiles.insert(tile).inserted else {
                continue
            }
            requiredTiles.append(tile)
            if requiredTiles.count == NightLightsAtlasSurfaceBinding.maxEntryCount {
                break
            }
        }

        return requiredTiles
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext: FrameContext, resourceRegistry _: RenderResourceRegistry) {
        guard frameContext.renderSurfaceMode == .spherical,
              frameContext.earthSceneUniform.isEnabled != 0,
              frameContext.earthSceneUniform.nightLightsEnabled != 0,
              let tileSet = tileSetStore.tileSet else {
            publishEmptyState(frameContext: frameContext)
            return
        }

        let visibleTiles = frameContext.sharedState.tilePlacementState
            .globeTexturePlaceTilesContext
            .tilePlacements
            .map(\.placeIn.tile)
        let requiredTiles = Self.renderableRequiredNightLightTiles(for: visibleTiles, tileSet: tileSet)
        tileCache.prefetchTiles(requiredTiles)
        let tileData = requiredTiles.compactMap { tileCache.tileData(for: $0) }
        let readyTiles = tileData.map(\.tile)

        guard requiredTiles != previousRequiredTiles || readyTiles != previousReadyTiles else {
            frameContext.sharedState.nightLightsAtlasState = atlasState
            return
        }

        atlasState = atlasTexture.update(tiles: tileData)
        previousRequiredTiles = requiredTiles
        previousReadyTiles = readyTiles
        frameContext.sharedState.nightLightsAtlasState = atlasState
    }

    func encode(layer _: RenderLayer, encoder _: MTLRenderCommandEncoder, frameContext _: FrameContext) {}

    func handleMemoryWarning() {
        clearCachedState()
    }

    func evict() {
        clearCachedState()
    }

    private func publishEmptyState(frameContext: FrameContext) {
        previousRequiredTiles = nil
        previousReadyTiles = nil
        atlasState = .empty
        frameContext.sharedState.nightLightsAtlasState = .empty
    }

    private func clearCachedState() {
        tileCache.removeAll()
        atlasTexture.removeAll()
        previousRequiredTiles = nil
        previousReadyTiles = nil
        atlasState = .empty
    }
}
