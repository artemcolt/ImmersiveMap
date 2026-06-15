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

    private var globeTextureVersionTracker = StagedHashChangeTracker()
    private var placeTilesContext: GlobeTexturePlaceTilesContext = .empty
    private var overviewFadeAlpha: Float = 1.0
    private var roadFadeAlpha: Float = 0.0
    private var globeAtlasDebugSummary: GlobeAtlasDebugSummary?

    init(tilesTexture: GlobeTilesTexture) {
        self.tilesTexture = tilesTexture
    }

    func update(frameContext: FrameContext) {
        frameContext.sharedState.globeAtlasDebugSummary = frameContext.renderSurfaceMode == .spherical ? globeAtlasDebugSummary : nil

        let tilePlacementState = frameContext.sharedState.tilePlacementState
        placeTilesContext = tilePlacementState.globeTexturePlaceTilesContext
        overviewFadeAlpha = LowZoomOverviewFade.alpha(for: frameContext.zoom, kind: .overviewFeatures)
        roadFadeAlpha = LowZoomOverviewFade.alpha(for: frameContext.zoom, kind: .roads)

        var hasher = Hasher()
        hasher.combine(Int(truncatingIfNeeded: tilePlacementState.placementVersion))
        hasher.combine(overviewFadeAlpha.bitPattern)
        hasher.combine(roadFadeAlpha.bitPattern)
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
        globeAtlasDebugSummary = nil
        globeTextureVersionTracker.invalidate()
    }

    func evict() {
        placeTilesContext = .empty
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
        let planner = GlobeAtlasPlacementPlanner(pageSizePx: tilesTexture.size,
                                                 qualityScale: 1.0)
        let candidates = planner.makeCandidates(placeTiles: placeTilesContext.tilePlacements,
                                                frameContext: frameContext)
        let atlasPlan = planner.plan(candidates: candidates)
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
}
