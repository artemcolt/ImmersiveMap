// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  GlobeViewSceneRenderSubsystem.swift
//  ImmersiveMap
//

import Metal

final class GlobeViewSceneRenderSubsystem: RenderSubsystem {
    let name: String = "GlobeViewScene"

    private let encodeGlobeScene: (MTLRenderCommandEncoder, FrameContext) -> Void

    init(starfieldRenderer: StarfieldRenderer,
         globeDepthState: MTLDepthStencilState,
         globeCapDepthState: MTLDepthStencilState,
         depthDisabledState: MTLDepthStencilState,
         globeCapRenderer: GlobeCapRenderer,
         globePipeline: GlobePipeline,
         mapSurfaceGridBuffers: MapSurfaceGridBuffers,
         tilesTexture: TilesTexture) {
        encodeGlobeScene = { renderEncoder, frameContext in
            RendererSceneDrawer.drawSphericalScene(renderEncoder: renderEncoder,
                                                   drawSize: frameContext.drawSize,
                                                   nowTime: frameContext.time,
                                                   cameraUniform: frameContext.cameraUniform,
                                                   cameraView: frameContext.cameraMatrices.view,
                                                   cameraEye: frameContext.cameraEye,
                                                   globe: frameContext.globeRenderUniform,
                                                   starfieldRenderer: starfieldRenderer,
                                                   globeDepthState: globeDepthState,
                                                   globeCapDepthState: globeCapDepthState,
                                                   depthDisabledState: depthDisabledState,
                                                   globeCapRenderer: globeCapRenderer,
                                                   globePipeline: globePipeline,
                                                   mapSurfaceGridBuffers: mapSurfaceGridBuffers,
                                                   tilesTexture: tilesTexture)
        }
    }

    init(encodeGlobeScene: @escaping (MTLRenderCommandEncoder, FrameContext) -> Void) {
        self.encodeGlobeScene = encodeGlobeScene
    }

    func update(frameContext: FrameContext) {}

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {}

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard pass == .scene, frameContext.renderSurfaceMode == .spherical else { return }
        encodeGlobeScene(encoder, frameContext)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
