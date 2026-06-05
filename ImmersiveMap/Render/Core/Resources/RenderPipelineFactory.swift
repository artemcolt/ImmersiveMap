// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  RenderPipelineFactory.swift
//  ImmersiveMap
//

import Metal
import QuartzCore

struct RenderPipelineBundle {
    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let extrudedTilePipeline: ExtrudedTilePipeline
    let globePipeline: GlobePipeline
    let starfieldRenderer: StarfieldRenderer
}

final class RenderPipelineFactory {
    private let metalContext: RenderMetalContext
    private let layer: CAMetalLayer
    private let config: ImmersiveMapSettings

    init(metalContext: RenderMetalContext,
         layer: CAMetalLayer,
         config: ImmersiveMapSettings) {
        self.metalContext = metalContext
        self.layer = layer
        self.config = config
    }

    func makeRenderPipelines() -> RenderPipelineBundle {
        let metalDevice = metalContext.device
        let library = metalContext.library
        let polygonPipeline = PolygonsPipeline(metalDevice: metalDevice, layer: layer, library: library)
        let tilePipeline = TilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        let extrudedTilePipeline = ExtrudedTilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        let globePipeline = GlobePipeline(metalDevice: metalDevice, layer: layer, library: library)
        let starfieldRenderer = StarfieldRenderer(metalDevice: metalDevice,
                                                  layer: layer,
                                                  library: library,
                                                  spaceColor: config.scene.space.clearColor,
                                                  config: config.scene.starfield)

        return RenderPipelineBundle(polygonPipeline: polygonPipeline,
                                    tilePipeline: tilePipeline,
                                    extrudedTilePipeline: extrudedTilePipeline,
                                    globePipeline: globePipeline,
                                    starfieldRenderer: starfieldRenderer)
    }
}
