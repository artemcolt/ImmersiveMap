// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore

final class RendererPassEncoderFactory {
    private init() {}

    static func makeRenderEncoder(commandBuffer: MTLCommandBuffer,
                                  drawable: CAMetalDrawable,
                                  clearColor: MTLClearColor,
                                  depthTexture: MTLTexture?) -> MTLRenderCommandEncoder {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        if let depthTexture {
            renderPassDescriptor.depthAttachment.texture = depthTexture
            renderPassDescriptor.depthAttachment.loadAction = .clear
            renderPassDescriptor.depthAttachment.storeAction = .dontCare
            renderPassDescriptor.depthAttachment.clearDepth = 1.0
        }
        return commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    }

    static func makeBuildingWinnerEncoder(commandBuffer: MTLCommandBuffer,
                                          winnerIDTexture: MTLTexture,
                                          winnerDepthTexture: MTLTexture) -> MTLRenderCommandEncoder {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = winnerIDTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        renderPassDescriptor.depthAttachment.texture = winnerDepthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        return commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    }
}
