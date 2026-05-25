//
//  CommonViewSceneRenderSubsystem.swift
//  ImmersiveMapFramework
//

import Metal

final class CommonViewSceneRenderSubsystem: RenderSubsystem {
    let name: String = "CommonViewScene"

    private let applyCommonSceneState: (MTLRenderCommandEncoder) -> Void

    init(depthDisabledState: MTLDepthStencilState) {
        applyCommonSceneState = { encoder in
            encoder.setDepthStencilState(depthDisabledState)
        }
    }

    init(applyCommonSceneState: @escaping (MTLRenderCommandEncoder) -> Void) {
        self.applyCommonSceneState = applyCommonSceneState
    }

    func update(frameContext: FrameContext) {}

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {}

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard pass == .scene else { return }
        applyCommonSceneState(encoder)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
