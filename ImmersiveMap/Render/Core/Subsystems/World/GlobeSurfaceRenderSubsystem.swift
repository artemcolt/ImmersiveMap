// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class GlobeSurfaceRenderSubsystem: RenderSubsystem {
    let name: String = "GlobeSurface"

    private let globeDepthState: MTLDepthStencilState
    private let globePipeline: GlobePipeline
    private let mapSurfaceGridBuffers: MapSurfaceGridBuffers
    private let nightLightsTexture: NightLightsTexture
    private let tilesTexture: GlobeTilesTexture
    private let debugOverlayControls: DebugOverlayControlState

    init(globeDepthState: MTLDepthStencilState,
         globePipeline: GlobePipeline,
         mapSurfaceGridBuffers: MapSurfaceGridBuffers,
         nightLightsTexture: NightLightsTexture,
         tilesTexture: GlobeTilesTexture,
         debugOverlayControls: DebugOverlayControlState) {
        self.globeDepthState = globeDepthState
        self.globePipeline = globePipeline
        self.mapSurfaceGridBuffers = mapSurfaceGridBuffers
        self.nightLightsTexture = nightLightsTexture
        self.tilesTexture = tilesTexture
        self.debugOverlayControls = debugOverlayControls
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .globeSurface,
              frameContext.renderSurfaceMode == .spherical else {
            return
        }

        let earthScene = frameContext.earthSceneUniform
        let nightTexture = earthScene.isEnabled != 0 && earthScene.nightLightsEnabled != 0
            ? nightLightsTexture.texture()
            : nightLightsTexture.placeholderTexture

        encoder.setDepthStencilState(globeDepthState)
        GlobeSurfaceDrawer.draw(renderEncoder: encoder,
                                cameraUniform: frameContext.cameraUniform,
                                globe: frameContext.globeRenderUniform,
                                earthScene: earthScene,
                                nightLightsTexture: nightTexture,
                                globePipeline: globePipeline,
                                mapSurfaceGridBuffers: mapSurfaceGridBuffers,
                                tilesTexture: tilesTexture,
                                isWireframeEnabled: debugOverlayControls.snapshot().wireframeEnabled)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
