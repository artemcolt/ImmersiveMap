// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import MetalKit
import QuartzCore

final class RenderStaticResources {
    let metalContext: RenderMetalContext
    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let extrudedTilePipeline: ExtrudedTilePipeline
    let globePipeline: GlobePipeline
    let globeCapRenderer: GlobeCapRenderer
    let starfield: Starfield
    let tileRenderStore: TileRenderStore
    let tilesTexture: TilesTexture
    let textRenderer: TextRenderer
    let poiSpriteAtlas: PoiSpriteAtlas
    let debugOverlayRenderer: DebugOverlayRenderer
    let baseGridBuffers: GridBuffers
    let flatTileOriginCalculator: FlatTileOriginCalculator
    let baseLabelCache: BaseLabelCache
    let roadLabelCache: RoadLabelCache
    let extrudedDepthState: MTLDepthStencilState
    let extrudedColorPassDepthState: MTLDepthStencilState
    let globeCapDepthState: MTLDepthStencilState
    let depthDisabledState: MTLDepthStencilState
    let avatarsControllerProvider: () -> ImmersiveMapAvatarsController?
    let avatarsRenderer: AvatarsRenderer

    init(layer: CAMetalLayer,
         avatarsControllerProvider: @escaping () -> ImmersiveMapAvatarsController?,
         config: ImmersiveMapSettings,
         onTileAvailable: @escaping (Tile) -> Void) {
        let metal = RendererSetup.buildMetal(layer: layer)
        self.metalContext = metal

        self.extrudedDepthState = metal.device.makeDepthStencilState(descriptor: Self.makeSceneDepthDescriptor())!
        self.extrudedColorPassDepthState = metal.device.makeDepthStencilState(descriptor: Self.makeTransparentExtrudedDepthDescriptor())!
        self.globeCapDepthState = metal.device.makeDepthStencilState(descriptor: Self.makeGlobeCapDepthDescriptor())!
        self.depthDisabledState = metal.device.makeDepthStencilState(descriptor: Self.makeDepthDisabledDescriptor())!

        let mapStyle = DefaultMapStyle(settings: config.style)
        let mapBaseColors = mapStyle.getMapBaseColors()

        let pipelineFactory = RenderPipelineFactory(metalContext: metal,
                                                    layer: layer,
                                                    config: config)
        let pipelines = pipelineFactory.makeRenderPipelines()
        self.polygonPipeline = pipelines.polygonPipeline
        self.tilePipeline = pipelines.tilePipeline
        self.extrudedTilePipeline = pipelines.extrudedTilePipeline
        self.globePipeline = pipelines.globePipeline
        self.starfield = pipelines.starfield

        self.textRenderer = TextRenderer(device: metal.device, library: metal.library)
        self.poiSpriteAtlas = PoiSpriteAtlas(device: metal.device)
        self.tilesTexture = TilesTexture(metalDevice: metal.device, tilePipeline: tilePipeline)
        self.debugOverlayRenderer = DebugOverlayRenderer(metalDevice: metal.device, settings: config.debug)
        self.baseGridBuffers = RendererSetup.makeBaseGridBuffers(metalDevice: metal.device)
        self.flatTileOriginCalculator = FlatTileOriginCalculator(metalDevice: metal.device)
        self.globeCapRenderer = GlobeCapRenderer(metalDevice: metal.device,
                                                 layer: layer,
                                                 library: metal.library,
                                                 maxLatitude: Self.maxLatitude,
                                                 mapBaseColors: mapBaseColors)
        self.tileRenderStore = TileRenderStore(mapStyle: mapStyle,
                                               metalDevice: metal.device,
                                               textRenderer: textRenderer,
                                               config: config)
        self.tileRenderStore.onTileAvailable = onTileAvailable
        self.baseLabelCache = BaseLabelCache(metalDevice: metal.device)
        self.roadLabelCache = RoadLabelCache(metalDevice: metal.device,
                                             textRenderer: textRenderer)
        self.avatarsControllerProvider = avatarsControllerProvider
        self.avatarsRenderer = AvatarsRenderer(metalDevice: metal.device,
                                               layer: layer,
                                               library: metal.library,
                                               config: config.avatars)
    }

    func applySettings(_ settings: ImmersiveMapSettings) {
        debugOverlayRenderer.apply(settings: settings.debug)
    }

    private static var maxLatitude: Double {
        2.0 * atan(exp(Double.pi)) - Double.pi / 2.0
    }

    private static func makeSceneDepthDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true
        return descriptor
    }

    private static func makeGlobeCapDepthDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = false
        return descriptor
    }

    private static func makeTransparentExtrudedDepthDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = false
        return descriptor
    }

    private static func makeDepthDisabledDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false
        return descriptor
    }
}
