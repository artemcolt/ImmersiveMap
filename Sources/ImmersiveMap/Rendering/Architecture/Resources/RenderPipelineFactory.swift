//
//  RenderPipelineFactory.swift
//  ImmersiveMapFramework
//

import Metal
import QuartzCore

struct RenderPipelineBundle {
    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let extrudedTilePipeline: ExtrudedTilePipeline
    let globePipeline: GlobePipeline
    let starfield: Starfield
}

final class RenderPipelineFactory {
    private let metalDevice: MTLDevice
    private let layer: CAMetalLayer
    private let library: MTLLibrary
    private let config: MapSettings

    init(metalDevice: MTLDevice,
         layer: CAMetalLayer,
         library: MTLLibrary,
         config: MapSettings) {
        self.metalDevice = metalDevice
        self.layer = layer
        self.library = library
        self.config = config
    }

    func makeRenderPipelines() -> RenderPipelineBundle {
        let polygonPipeline = PolygonsPipeline(metalDevice: metalDevice, layer: layer, library: library)
        let tilePipeline = TilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        let extrudedTilePipeline = ExtrudedTilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        let globePipeline = GlobePipeline(metalDevice: metalDevice, layer: layer, library: library)
        let starfield = Starfield(metalDevice: metalDevice,
                                  layer: layer,
                                  library: library,
                                  spaceColor: config.scene.space.clearColor,
                                  config: config.scene.starfield)

        return RenderPipelineBundle(polygonPipeline: polygonPipeline,
                                    tilePipeline: tilePipeline,
                                    extrudedTilePipeline: extrudedTilePipeline,
                                    globePipeline: globePipeline,
                                    starfield: starfield)
    }
}
