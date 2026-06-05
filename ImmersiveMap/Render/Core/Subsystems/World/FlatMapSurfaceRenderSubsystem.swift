// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class FlatMapSurfaceRenderSubsystem: RenderSubsystem {
    let name: String = "FlatMapSurface"

    private let tilePipeline: TilePipeline
    private let separateRoadRenderingMinimumZoom: Int

    init(tilePipeline: TilePipeline,
         separateRoadRenderingMinimumZoom: Int) {
        self.tilePipeline = tilePipeline
        self.separateRoadRenderingMinimumZoom = separateRoadRenderingMinimumZoom
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .flatMapSurface,
              frameContext.renderSurfaceMode == .flat else {
            return
        }

        FlatMapSurfaceDrawer.draw(renderEncoder: encoder,
                                  cameraUniform: frameContext.cameraUniform,
                                  cameraZoom: frameContext.zoom,
                                  separateRoadRenderingMinimumZoom: separateRoadRenderingMinimumZoom,
                                  placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                  flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                  tilePipeline: tilePipeline)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
