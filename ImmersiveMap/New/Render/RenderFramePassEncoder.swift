// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore

/// Кодирует render passes одного кадра: готовит drawable, attachments, pass plan и вызывает subsystem encoders.
final class RenderFramePassEncoder {
    private let attachments: FrameAttachmentStore
    private let renderGraph: RenderGraph

    init(attachments: FrameAttachmentStore,
         renderGraph: RenderGraph) {
        self.attachments = attachments
        self.renderGraph = renderGraph
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

        let resourceRegistry = renderGraph.resourceRegistry
        let clearColor = RenderFrameClearColor.make(transition: frameContext.transition,
                                                    settings: settings)
        let depthTexture = attachments.ensureDepthTexture(drawSize: frameContext.drawSize)
        if let depthTexture {
            resourceRegistry.setTexture(depthTexture, named: .depthTexture)
        }
        renderGraph.preparePrePasses(frameContext: frameContext,
                                     attachments: attachments)
        renderGraph.encodePrePasses(commandBuffer: commandBuffer,
                                    frameContext: frameContext)

        let renderEncoder = RendererPassEncoderFactory.makeRenderEncoder(commandBuffer: commandBuffer,
                                                                         drawable: drawable,
                                                                         clearColor: clearColor,
                                                                         depthTexture: depthTexture)
        let passAvailability = renderGraph.passAvailability(settings: settings)
        let passPlan = RenderPassPlanner.plan(availability: passAvailability)

        for planItem in passPlan {
            guard planItem.enabled else {
                if let reason = planItem.skipReason {
                    frameContext.services.diagnostics.recordSkipReason(reason)
                }
                continue
            }

            let passStart = CACurrentMediaTime()
            renderGraph.encode(pass: planItem.pass,
                               encoder: renderEncoder,
                               frameContext: frameContext)
            frameContext.diagnostics.recordPass(planItem.pass,
                                                duration: CACurrentMediaTime() - passStart)
        }

        renderEncoder.endEncoding()
        return drawable
    }
}
