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

    private let tilesTexture: TilesTexture

    private var globeTextureVersionTracker = StagedHashChangeTracker()
    private var placeTilesContext: PlaceTilesContext = .empty
    private var overviewFadeAlpha: Float = 1.0
    private var roadFadeAlpha: Float = 0.0

    init(tilesTexture: TilesTexture) {
        self.tilesTexture = tilesTexture
    }

    func update(frameContext: FrameContext) {
        let tilePlacementState = frameContext.sharedState.tilePlacementState
        placeTilesContext = tilePlacementState.placeTilesContext
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
        globeTextureVersionTracker.invalidate()
    }

    func evict() {
        placeTilesContext = .empty
        globeTextureVersionTracker.invalidate()
    }

    private func renderGlobeTilesTextureIfNeeded(commandBuffer: MTLCommandBuffer,
                                                 frameContext: FrameContext) {
        guard frameContext.renderSurfaceMode == .spherical else { return }

        tilesTexture.activateEncoder(commandBuffer: commandBuffer)
        tilesTexture.setOverviewFadeAlphas(overviewAlpha: overviewFadeAlpha,
                                           roadAlpha: roadFadeAlpha)
        drawGlobeTexture()
        tilesTexture.endEncoding()
    }

    private func drawGlobeTexture() {
        // Globe atlas path: assign atlas depth during draw and stop when capacity is exhausted.
        tilesTexture.selectTilePipeline()
        let tileDepthCount = TileDepthCount()
        for placeTile in placeTilesContext.tilePlacements {
            guard let atlasDepth = tileDepthCount.getTexturePlaceDepth() else {
                break
            }

            let placed = tilesTexture.draw(placeTile: placeTile,
                                           atlasDepth: atlasDepth,
                                           maxDepth: 4)
            if placed == false {
                #if DEBUG
                print("[ERROR] No place for tile in texture!")
                #endif
                break
            }
        }
    }
}
