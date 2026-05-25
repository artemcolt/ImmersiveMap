//
//  RenderSubsystem.swift
//  ImmersiveMapFramework
//

import Metal

protocol RenderSubsystem: AnyObject {
    var name: String { get }

    func update(frameContext: FrameContext)
    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry)
    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext)
    func handleMemoryWarning()
    func evict()
}
