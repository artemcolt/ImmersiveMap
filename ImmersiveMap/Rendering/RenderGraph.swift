// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

/// Runtime graph of render subsystems, pre-passes, shared frame resources, and pass availability providers.
final class RenderGraph {
    let resourceRegistry: RenderResourceRegistry

    private let registry: RenderSubsystemRegistry
    private let prePasses: [any RenderFramePrePass]
    private let availabilityProviders: [any RenderPassAvailabilityProvider]

    init(registry: RenderSubsystemRegistry,
         prePasses: [any RenderFramePrePass],
         availabilityProviders: [any RenderPassAvailabilityProvider],
         resourceRegistry: RenderResourceRegistry = RenderResourceRegistry()) {
        self.registry = registry
        self.prePasses = prePasses
        self.availabilityProviders = availabilityProviders
        self.resourceRegistry = resourceRegistry
    }

    func passAvailability(settings: ImmersiveMapSettings) -> RenderPassAvailability {
        var builder = RenderPassAvailabilityBuilder()
        for provider in availabilityProviders {
            provider.contributePassAvailability(settings: settings,
                                                builder: &builder)
        }
        return builder.build()
    }

    func update(frameContext: FrameContext) {
        registry.update(frameContext: frameContext)
    }

    func prepareGPU(frameContext: FrameContext) {
        registry.prepareGPU(frameContext: frameContext,
                            resourceRegistry: resourceRegistry)
    }

    func preparePrePasses(frameContext: FrameContext,
                          attachments: FrameAttachmentStore) {
        for prePass in prePasses {
            prePass.prepare(frameContext: frameContext,
                            attachments: attachments,
                            resourceRegistry: resourceRegistry)
        }
    }

    func encodePrePasses(commandBuffer: MTLCommandBuffer,
                         frameContext: FrameContext) {
        for prePass in prePasses {
            prePass.encode(commandBuffer: commandBuffer,
                           frameContext: frameContext)
        }
    }

    func encode(pass: RenderPass,
                encoder: MTLRenderCommandEncoder,
                frameContext: FrameContext) {
        registry.encode(pass: pass,
                        encoder: encoder,
                        frameContext: frameContext)
    }

    func handleMemoryWarning() {
        registry.handleMemoryWarning()
        for prePass in prePasses {
            prePass.handleMemoryWarning()
        }
    }

    func evict() {
        registry.evict()
        for prePass in prePasses {
            prePass.evict()
        }
    }
}
