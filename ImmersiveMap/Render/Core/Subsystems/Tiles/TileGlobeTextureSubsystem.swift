// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  TileGlobeTextureSubsystem.swift
//  ImmersiveMap
//

import Foundation
import Metal

final class TileGlobeTextureSubsystem: RenderSubsystem {
    let name: String = "Tiles"

    private let tilesTexture: GlobeTilesTexture

    private let atlasQualityScale: Float = 1.0
    private var globeTextureVersionTracker = StagedHashChangeTracker()
    private var atlasPlanCacheKey: GlobeAtlasPlanCacheKey?
    private var placeTilesContext: GlobeTexturePlaceTilesContext = .empty
    private var atlasPlan: GlobeAtlasPlan = .empty
    private var overviewFadeAlpha: Float = 1.0
    private var roadFadeAlpha: Float = 0.0
    private var globeAtlasDebugSummary: GlobeAtlasDebugSummary?

    init(tilesTexture: GlobeTilesTexture) {
        self.tilesTexture = tilesTexture
    }

    func update(frameContext: FrameContext) {
        let tilePlacementState = frameContext.sharedState.tilePlacementState
        placeTilesContext = tilePlacementState.globeTexturePlaceTilesContext
        overviewFadeAlpha = LowZoomOverviewFade.alpha(for: frameContext.zoom, kind: .overviewFeatures)
        roadFadeAlpha = LowZoomOverviewFade.alpha(for: frameContext.zoom, kind: .roads)
        updateAtlasPlanIfNeeded(frameContext: frameContext,
                                placementVersion: tilePlacementState.placementVersion)
        frameContext.sharedState.globeAtlasDebugSummary = frameContext.renderSurfaceMode == .spherical ? globeAtlasDebugSummary : nil

        var hasher = Hasher()
        hasher.combine(Int(truncatingIfNeeded: tilePlacementState.placementVersion))
        hasher.combine(overviewFadeAlpha.bitPattern)
        hasher.combine(roadFadeAlpha.bitPattern)
        combineAtlasPlanHash(atlasPlan, into: &hasher)
        _ = globeTextureVersionTracker.stage(hasher.finalize())
    }

    func prepareGPU(frameContext: FrameContext, resourceRegistry _: RenderResourceRegistry) {
        guard globeTextureVersionTracker.hasPendingChange else {
            return
        }
        guard let commandBuffer = frameContext.commandBuffer else {
            frameContext.services.diagnostics.recordSkipReason(.missingCommandBuffer)
            return
        }

        renderGlobeTilesTextureIfNeeded(commandBuffer: commandBuffer, frameContext: frameContext)
        globeTextureVersionTracker.commitPending()
    }

    func encode(layer _: RenderLayer, encoder _: MTLRenderCommandEncoder, frameContext _: FrameContext) {}

    func handleMemoryWarning() {
        placeTilesContext = .empty
        atlasPlan = .empty
        atlasPlanCacheKey = nil
        globeAtlasDebugSummary = nil
        globeTextureVersionTracker.invalidate()
    }

    func evict() {
        placeTilesContext = .empty
        atlasPlan = .empty
        atlasPlanCacheKey = nil
        globeAtlasDebugSummary = nil
        globeTextureVersionTracker.invalidate()
    }

    private func renderGlobeTilesTextureIfNeeded(commandBuffer: MTLCommandBuffer,
                                                 frameContext: FrameContext) {
        guard frameContext.renderSurfaceMode == .spherical else { return }

        drawGlobeTexture(commandBuffer: commandBuffer, frameContext: frameContext)
    }

    private func drawGlobeTexture(commandBuffer: MTLCommandBuffer,
                                  frameContext: FrameContext) {
        tilesTexture.resetFrame()
        let atlasDebugSummary = GlobeAtlasDebugSummary(plan: atlasPlan)
        globeAtlasDebugSummary = atlasDebugSummary
        frameContext.sharedState.globeAtlasDebugSummary = atlasDebugSummary

        let allocationsByPage = Dictionary(grouping: atlasPlan.allocations, by: \.pageIndex)

        for pageIndex in allocationsByPage.keys.sorted() {
            guard let allocations = allocationsByPage[pageIndex],
                  tilesTexture.beginPageEncoding(commandBuffer: commandBuffer, pageIndex: pageIndex) else {
                continue
            }

            tilesTexture.setOverviewFadeAlphas(overviewAlpha: overviewFadeAlpha,
                                               roadAlpha: roadFadeAlpha)
            tilesTexture.selectTilePipeline()

            for allocation in allocations {
                let placed = tilesTexture.draw(allocation: allocation, maxDepth: 4)
                if placed == false {
                    #if DEBUG
                    print("[ERROR] No place for tile in globe atlas texture!")
                    #endif
                    break
                }
            }

            tilesTexture.endEncoding()
        }
    }

    private func makeAtlasPlan(frameContext: FrameContext) -> GlobeAtlasPlan {
        guard frameContext.renderSurfaceMode == .spherical else { return .empty }

        let planner = GlobeAtlasPlacementPlanner(pageSizePx: tilesTexture.size,
                                                 qualityScale: atlasQualityScale)
        let candidates = planner.makeCandidates(placeTiles: placeTilesContext.tilePlacements,
                                                frameContext: frameContext)
        return planner.plan(candidates: candidates)
    }

    private func updateAtlasPlanIfNeeded(frameContext: FrameContext,
                                         placementVersion: UInt64) {
        let cacheKey = GlobeAtlasPlanCacheKey(renderSurfaceMode: frameContext.renderSurfaceMode,
                                             placementVersion: placementVersion,
                                             drawSize: frameContext.drawSize,
                                             cameraUniform: frameContext.cameraUniform,
                                             globe: frameContext.globeRenderUniform,
                                             textureSize: tilesTexture.size,
                                             qualityScale: atlasQualityScale)
        guard atlasPlanCacheKey != cacheKey else {
            return
        }

        atlasPlan = makeAtlasPlan(frameContext: frameContext)
        atlasPlanCacheKey = cacheKey
        globeAtlasDebugSummary = GlobeAtlasDebugSummary(plan: atlasPlan)
    }

    private func combineAtlasPlanHash(_ atlasPlan: GlobeAtlasPlan,
                                      into hasher: inout Hasher) {
        hasher.combine(atlasPlan.allocations.count)
        hasher.combine(atlasPlan.pageSummaries.count)
        hasher.combine(atlasPlan.downgradedAllocationCount)
        hasher.combine(atlasPlan.skippedAllocationCount)

        for allocation in atlasPlan.allocations {
            hasher.combine(allocation.pageIndex)
            hasher.combine(allocation.placedPosition.x)
            hasher.combine(allocation.placedPosition.y)
            hasher.combine(allocation.atlasDepth.rawValue)
            hasher.combine(allocation.cellSizePx)
            hasher.combine(allocation.placeTile.metalTile.tile)
            hasher.combine(allocation.placeTile.placeIn.tile)
            hasher.combine(allocation.placeTile.lodKind)
        }
    }
}
