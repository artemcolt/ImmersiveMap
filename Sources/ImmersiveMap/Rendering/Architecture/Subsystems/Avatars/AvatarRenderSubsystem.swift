//
//  AvatarRenderSubsystem.swift
//  ImmersiveMapFramework
//

import Metal

final class AvatarRenderSubsystem: RenderSubsystem {
    let name: String = "Avatars"

    private let avatarsRenderer: AvatarsRenderer
    private let avatarsController: AvatarsController
    private let depthDisabledState: MTLDepthStencilState

    var hasRenderableAvatars: Bool {
        avatarsRenderer.hasRenderableAvatars
    }

    init(avatarsRenderer: AvatarsRenderer,
         avatarsController: AvatarsController,
         depthDisabledState: MTLDepthStencilState) {
        self.avatarsRenderer = avatarsRenderer
        self.avatarsController = avatarsController
        self.depthDisabledState = depthDisabledState
    }

    func update(frameContext: FrameContext) {
        avatarsRenderer.update(controller: avatarsController,
                               time: frameContext.time)
        frameContext.sharedState.avatarState.hasActiveAnimations = avatarsRenderer.hasActiveAnimations
    }

    func prepareGPU(frameContext: FrameContext, resourceRegistry _: RenderResourceRegistry) {
        guard let commandBuffer = frameContext.commandBuffer else {
            frameContext.services.diagnostics.recordSkipReason(.missingCommandBuffer)
            return
        }

        avatarsRenderer.compute(drawSize: frameContext.drawSize,
                                cameraUniform: frameContext.cameraUniform,
                                resolvedPresentation: frameContext.resolvedPresentation,
                                commandBuffer: commandBuffer)
        frameContext.sharedState.avatarState.selectionSnapshot = avatarsRenderer.selectionSnapshot
            .withFrameIndex(frameContext.frameIndex)
    }

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard pass == .avatars else { return }
        encoder.setDepthStencilState(depthDisabledState)
        RendererAvatarDrawer.drawAvatars(renderEncoder: encoder,
                                         screenMatrix: frameContext.cameraMatrices.screen,
                                         time: Float(frameContext.time),
                                         avatarsRenderer: avatarsRenderer)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
