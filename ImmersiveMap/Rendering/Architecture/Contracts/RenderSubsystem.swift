// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  RenderSubsystem.swift
//  ImmersiveMap
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
