// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class GlobeSurfaceRenderSubsystem: RenderSubsystem {
    let name: String = "GlobeSurface"

    private let globeDepthState: MTLDepthStencilState
    private let globePipeline: GlobePipeline
    private let mapSurfaceGridBuffers: MapSurfaceGridBuffers
    private let tilesTexture: GlobeTilesTexture

    init(globeDepthState: MTLDepthStencilState,
         globePipeline: GlobePipeline,
         mapSurfaceGridBuffers: MapSurfaceGridBuffers,
         tilesTexture: GlobeTilesTexture) {
        self.globeDepthState = globeDepthState
        self.globePipeline = globePipeline
        self.mapSurfaceGridBuffers = mapSurfaceGridBuffers
        self.tilesTexture = tilesTexture
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .globeSurface,
              frameContext.renderSurfaceMode == .spherical else {
            return
        }

        encoder.setDepthStencilState(globeDepthState)
        GlobeSurfaceDrawer.draw(renderEncoder: encoder,
                                cameraUniform: frameContext.cameraUniform,
                                globe: frameContext.globeRenderUniform,
                                globePipeline: globePipeline,
                                mapSurfaceGridBuffers: mapSurfaceGridBuffers,
                                tilesTexture: tilesTexture)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
