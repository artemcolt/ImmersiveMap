//
//  GlobeViewSceneRenderSubsystem.swift
//  ImmersiveMapFramework
//

import Metal

final class GlobeViewSceneRenderSubsystem: RenderSubsystem {
    let name: String = "GlobeViewScene"

    private let encodeGlobeScene: (MTLRenderCommandEncoder, FrameContext) -> Void

    init(camera: Camera,
         starfield: Starfield,
         globeDepthState: MTLDepthStencilState,
         globeCapDepthState: MTLDepthStencilState,
         depthDisabledState: MTLDepthStencilState,
         globeCapRenderer: GlobeCapRenderer,
         globePipeline: GlobePipeline,
         baseGridBuffers: GridBuffers,
         tilesTexture: TilesTexture) {
        encodeGlobeScene = { renderEncoder, frameContext in
            RendererSceneDrawer.drawSphericalScene(renderEncoder: renderEncoder,
                                                   drawSize: frameContext.drawSize,
                                                   nowTime: frameContext.time,
                                                   cameraUniform: frameContext.cameraUniform,
                                                   cameraView: frameContext.cameraMatrices.view,
                                                   cameraEye: camera.eye,
                                                   globe: frameContext.globeRenderUniform,
                                                   starfield: starfield,
                                                   globeDepthState: globeDepthState,
                                                   globeCapDepthState: globeCapDepthState,
                                                   depthDisabledState: depthDisabledState,
                                                   globeCapRenderer: globeCapRenderer,
                                                   globePipeline: globePipeline,
                                                   baseGridBuffers: baseGridBuffers,
                                                   tilesTexture: tilesTexture)
        }
    }

    init(encodeGlobeScene: @escaping (MTLRenderCommandEncoder, FrameContext) -> Void) {
        self.encodeGlobeScene = encodeGlobeScene
    }

    func update(frameContext: FrameContext) {}

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {}

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard pass == .scene, frameContext.renderBackendMode == .spherical else { return }
        encodeGlobeScene(encoder, frameContext)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
