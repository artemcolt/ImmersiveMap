// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore

final class RenderPassGraph {
    private final class BuildingWinnerDescriptorProvider: RenderPassDescriptorProvider {
        func makeRenderPassDescriptor(frameContext: FrameContext,
                                      attachments: FrameAttachmentStore,
                                      drawable _: CAMetalDrawable?) -> MTLRenderPassDescriptor? {
            guard frameContext.renderSurfaceMode == .flat,
                  let winnerIDTexture = attachments.ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
                  let winnerDepthTexture = attachments.ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) else {
                return nil
            }

            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = winnerIDTexture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            descriptor.depthAttachment.texture = winnerDepthTexture
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .dontCare
            descriptor.depthAttachment.clearDepth = 1.0
            return descriptor
        }
    }

    private final class MainDrawableDescriptorProvider: RenderPassDescriptorProvider {
        private let clearColor: MTLClearColor
        private let depthTexture: MTLTexture?

        init(clearColor: MTLClearColor,
             depthTexture: MTLTexture?) {
            self.clearColor = clearColor
            self.depthTexture = depthTexture
        }

        func makeRenderPassDescriptor(frameContext _: FrameContext,
                                      attachments _: FrameAttachmentStore,
                                      drawable: CAMetalDrawable?) -> MTLRenderPassDescriptor? {
            guard let drawable else {
                return nil
            }

            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = drawable.texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = clearColor
            descriptor.colorAttachments[0].storeAction = .store
            if let depthTexture {
                descriptor.depthAttachment.texture = depthTexture
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.storeAction = .dontCare
                descriptor.depthAttachment.clearDepth = 1.0
            }
            return descriptor
        }
    }

    func plan(frameContext: FrameContext,
              settings: ImmersiveMapSettings,
              attachments: FrameAttachmentStore,
              drawable: CAMetalDrawable,
              renderGraph: RenderGraph) -> [RenderPassNode] {
        let resourceRegistry = renderGraph.resourceRegistry
        let depthTexture = attachments.ensureDepthTexture(drawSize: frameContext.drawSize)
        if let depthTexture {
            resourceRegistry.setTexture(depthTexture, named: .depthTexture)
        }

        let clearColor = RenderFrameClearColor.make(transition: frameContext.transition,
                                                    settings: settings)
        let layerAvailability = renderGraph.passAvailability(settings: settings)
        let layerPlan = RenderLayerPlanner.plan(availability: layerAvailability)
            .filter(\.enabled)
            .map(\.layer)

        var nodes: [RenderPassNode] = []
        if frameContext.renderSurfaceMode == .flat,
           let winnerIDTexture = attachments.ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
           let winnerDepthTexture = attachments.ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) {
            resourceRegistry.setTexture(winnerIDTexture, named: .buildingWinnerIDTexture)
            resourceRegistry.setTexture(winnerDepthTexture, named: .buildingWinnerDepthTexture)
            nodes.append(RenderPassNode(name: .buildingWinner,
                                        descriptorProvider: BuildingWinnerDescriptorProvider(),
                                        layers: [.buildingWinner]))
        }
        nodes.append(RenderPassNode(name: .mainDrawable,
                                    descriptorProvider: MainDrawableDescriptorProvider(clearColor: clearColor,
                                                                                       depthTexture: depthTexture),
                                    layers: layerPlan))
        return nodes
    }
}
