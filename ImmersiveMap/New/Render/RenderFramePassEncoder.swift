// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore

/// Кодирует render passes одного кадра: готовит drawable, attachments, pass plan и вызывает subsystem encoders.
final class RenderFramePassEncoder {
    private let context: RenderPersistentContext
    private let attachments: FrameAttachmentStore
    private let subsystemGraph: RenderSubsystemGraph

    init(context: RenderPersistentContext,
         attachments: FrameAttachmentStore,
         subsystemGraph: RenderSubsystemGraph) {
        self.context = context
        self.attachments = attachments
        self.subsystemGraph = subsystemGraph
    }

    func encode(frameContext: FrameContext,
                layer: CAMetalLayer,
                settings: ImmersiveMapSettings) -> CAMetalDrawable? {
        guard let commandBuffer = frameContext.commandBuffer else {
            frameContext.services.diagnostics.recordSkipReason(.missingCommandBuffer)
            return nil
        }

        guard let drawable = layer.nextDrawable() else {
            frameContext.services.diagnostics.recordSkipReason(.missingDrawable)
            return nil
        }

        let resourceRegistry = subsystemGraph.resourceRegistry
        let clearColor = RenderFrameClearColor.make(transition: frameContext.transition,
                                                    settings: settings)
        let depthTexture = attachments.ensureDepthTexture(drawSize: frameContext.drawSize)
        if let depthTexture {
            resourceRegistry.setTexture(depthTexture, named: .depthTexture)
        }
        if frameContext.renderSurfaceMode == .flat,
           let winnerIDTexture = attachments.ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
           let winnerDepthTexture = attachments.ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) {
            resourceRegistry.setTexture(winnerIDTexture, named: .buildingWinnerIDTexture)
            resourceRegistry.setTexture(winnerDepthTexture, named: .buildingWinnerDepthTexture)
            RendererSceneDrawer.drawExtrudedWinnerPass(commandBuffer: commandBuffer,
                                                       cameraUniform: frameContext.cameraUniform,
                                                       placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                                       flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                                       winnerIDTexture: winnerIDTexture,
                                                       winnerDepthTexture: winnerDepthTexture,
                                                       extrudedTilePipeline: context.extrudedTilePipeline,
                                                       extrudedDepthState: context.extrudedDepthState)
        }

        let renderEncoder = RendererPassEncoderFactory.makeRenderEncoder(commandBuffer: commandBuffer,
                                                                         drawable: drawable,
                                                                         clearColor: clearColor,
                                                                         depthTexture: depthTexture)
        let availability = subsystemGraph.passAvailability
        let passAvailability = RenderPassAvailability(labelsEnabled: availability.labelsEnabled,
                                                      avatarsEnabled: availability.avatarsEnabled,
                                                      debugOverlayEnabled: RenderDebugOverlayPolicy.shouldEncode(settings.debug))
        let passPlan = RenderPassPlanner.plan(availability: passAvailability)

        for planItem in passPlan {
            guard planItem.enabled else {
                if let reason = planItem.skipReason {
                    frameContext.services.diagnostics.recordSkipReason(reason)
                }
                continue
            }

            let passStart = CACurrentMediaTime()
            subsystemGraph.encode(pass: planItem.pass,
                                  encoder: renderEncoder,
                                  frameContext: frameContext)
            frameContext.diagnostics.recordPass(planItem.pass,
                                                duration: CACurrentMediaTime() - passStart)
        }

        renderEncoder.endEncoding()
        return drawable
    }
}
