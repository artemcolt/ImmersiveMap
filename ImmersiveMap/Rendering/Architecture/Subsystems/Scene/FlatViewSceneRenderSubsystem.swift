// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  FlatViewSceneRenderSubsystem.swift
//  ImmersiveMap
//

import Metal

final class FlatViewSceneRenderSubsystem: RenderSubsystem {
    let name: String = "FlatViewScene"

    private let encodeFlatAndExtrudedScene: (MTLRenderCommandEncoder, FrameContext) -> Void

    init(tilePipeline: TilePipeline,
         separateRoadRenderingMinimumZoom: Int,
         buildingExtrusionAlpha: Float,
         buildingWinnerIDTextureProvider: @escaping () -> MTLTexture?,
         extrudedTilePipeline: ExtrudedTilePipeline,
         extrudedColorPassDepthState: MTLDepthStencilState,
         depthDisabledState: MTLDepthStencilState) {
        encodeFlatAndExtrudedScene = { renderEncoder, frameContext in
            let placeTilesContext = frameContext.sharedState.tilePlacementState.placeTilesContext
            let cameraUniform = frameContext.cameraUniform
            RendererSceneDrawer.drawFlatScene(renderEncoder: renderEncoder,
                                              cameraUniform: cameraUniform,
                                              cameraZoom: frameContext.zoom,
                                              separateRoadRenderingMinimumZoom: separateRoadRenderingMinimumZoom,
                                              placeTilesContext: placeTilesContext,
                                              flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                              tilePipeline: tilePipeline)

            RendererSceneDrawer.drawExtrudedScene(renderEncoder: renderEncoder,
                                                  cameraUniform: cameraUniform,
                                                  placeTilesContext: placeTilesContext,
                                                  flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                                  buildingExtrusionAlpha: buildingExtrusionAlpha,
                                                  winnerIDTexture: buildingWinnerIDTextureProvider(),
                                                  extrudedTilePipeline: extrudedTilePipeline,
                                                  extrudedColorPassDepthState: extrudedColorPassDepthState,
                                                  depthDisabledState: depthDisabledState)
        }
    }

    init(encodeFlatAndExtrudedScene: @escaping (MTLRenderCommandEncoder, FrameContext) -> Void) {
        self.encodeFlatAndExtrudedScene = encodeFlatAndExtrudedScene
    }

    func update(frameContext: FrameContext) {}

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .scene, frameContext.renderSurfaceMode == .flat else { return }
        encodeFlatAndExtrudedScene(encoder, frameContext)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
