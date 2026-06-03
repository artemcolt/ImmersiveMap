// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  DebugOverlayRenderSubsystem.swift
//  ImmersiveMap
//

import Metal

final class DebugOverlayRenderSubsystem: RenderSubsystem {
    let name: String = "DebugOverlay"

    private let polygonPipeline: PolygonsPipeline
    private let debugOverlayRenderer: DebugOverlayRenderer
    private let textRenderer: TextRenderer

    init(polygonPipeline: PolygonsPipeline,
         debugOverlayRenderer: DebugOverlayRenderer,
         textRenderer: TextRenderer) {
        self.polygonPipeline = polygonPipeline
        self.debugOverlayRenderer = debugOverlayRenderer
        self.textRenderer = textRenderer
    }

    func update(frameContext: FrameContext) {}

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {}

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard pass == .debugOverlay else { return }
        RendererDebugOverlayDrawer.draw(renderEncoder: encoder,
                                        frameContext: frameContext,
                                        polygonPipeline: polygonPipeline,
                                        debugOverlayRenderer: debugOverlayRenderer,
                                        textRenderer: textRenderer)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
