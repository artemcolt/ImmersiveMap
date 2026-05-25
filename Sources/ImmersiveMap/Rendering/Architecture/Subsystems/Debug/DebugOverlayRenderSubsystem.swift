//
//  DebugOverlayRenderSubsystem.swift
//  ImmersiveMapFramework
//

import Metal

final class DebugOverlayRenderSubsystem: RenderSubsystem {
    let name: String = "DebugOverlay"

    private let polygonPipeline: PolygonsPipeline
    private let debugOverlayRenderer: DebugOverlayRenderer
    private let textRenderer: TextRenderer
    private let cameraControl: CameraControl

    init(polygonPipeline: PolygonsPipeline,
         debugOverlayRenderer: DebugOverlayRenderer,
         textRenderer: TextRenderer,
         cameraControl: CameraControl) {
        self.polygonPipeline = polygonPipeline
        self.debugOverlayRenderer = debugOverlayRenderer
        self.textRenderer = textRenderer
        self.cameraControl = cameraControl
    }

    func update(frameContext: FrameContext) {}

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {}

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard pass == .debugOverlay else { return }
        RendererDebugOverlayDrawer.draw(renderEncoder: encoder,
                                        frameContext: frameContext,
                                        polygonPipeline: polygonPipeline,
                                        debugOverlayRenderer: debugOverlayRenderer,
                                        textRenderer: textRenderer,
                                        cameraControl: cameraControl)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
