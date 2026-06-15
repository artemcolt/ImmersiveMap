// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class GlobeCapRenderSubsystem: RenderSubsystem {
    let name: String = "GlobeCap"

    private let globeCapDepthState: MTLDepthStencilState
    private let depthDisabledState: MTLDepthStencilState
    private let globeCapRenderer: GlobeCapRenderer
    private let nightLightsTexture: NightLightsTexture
    private let tilesTexture: GlobeTilesTexture

    init(globeCapDepthState: MTLDepthStencilState,
         depthDisabledState: MTLDepthStencilState,
         globeCapRenderer: GlobeCapRenderer,
         nightLightsTexture: NightLightsTexture,
         tilesTexture: GlobeTilesTexture) {
        self.globeCapDepthState = globeCapDepthState
        self.depthDisabledState = depthDisabledState
        self.globeCapRenderer = globeCapRenderer
        self.nightLightsTexture = nightLightsTexture
        self.tilesTexture = tilesTexture
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .globeCap,
              frameContext.renderSurfaceMode == .spherical else {
            return
        }

        let earthScene = frameContext.earthSceneUniform
        let nightTexture = earthScene.isEnabled != 0 && earthScene.nightLightsEnabled != 0
            ? nightLightsTexture.texture()
            : nightLightsTexture.placeholderTexture

        encoder.setDepthStencilState(globeCapDepthState)
        globeCapRenderer.draw(renderEncoder: encoder,
                              cameraUniform: frameContext.cameraUniform,
                              globe: frameContext.globeRenderUniform,
                              earthScene: earthScene,
                              nightLightsTexture: nightTexture,
                              tilesTexture: tilesTexture)

        encoder.setDepthStencilState(depthDisabledState)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
