// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  CommonViewSceneRenderSubsystem.swift
//  ImmersiveMap
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

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .scene else { return }
        applyCommonSceneState(encoder)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
