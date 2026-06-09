// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import MetalKit
import QuartzCore

/// Долгоживущий контекст renderer lifecycle: собирает Metal-ресурсы, caches и renderer services,
/// которые переиспользуются subsystem graph и frame pipeline между кадрами.
final class RenderPersistentContext {
    // MARK: - Metal Core

    let metalContext: RenderMetalContext

    // MARK: - Pipelines

    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let extrudedTilePipeline: ExtrudedTilePipeline
    let globePipeline: GlobePipeline

    // MARK: - Scene Resources

    let globeCapRenderer: GlobeCapRenderer
    let starfieldRenderer: StarfieldRenderer
    let nightLightsTexture: NightLightsTexture
    let mapSurfaceGridBuffers: MapSurfaceGridBuffers
    let flatTileOriginCalculator: FlatTileOriginCalculator
    let extrudedDepthState: MTLDepthStencilState
    let extrudedColorPassDepthState: MTLDepthStencilState
    let globeCapDepthState: MTLDepthStencilState
    let depthDisabledState: MTLDepthStencilState

    // MARK: - Tile and Label Resources

    let tileRenderStore: TileRenderStore
    let tilesTexture: GlobeTilesTexture
    let textRenderer: TextRenderer
    let poiSpriteAtlas: PoiSpriteAtlas
    let baseLabelCache: BaseLabelCache
    let roadLabelCache: RoadLabelCache

    // MARK: - Avatar and Debug Resources

    let avatarSource: AvatarRenderSource
    let avatarsRenderer: AvatarsRenderer
    let debugOverlayRenderer: DebugOverlayRenderer

    // MARK: - Initialization

    init(layer: CAMetalLayer,
         avatarSource: AvatarRenderSource,
         config: ImmersiveMapSettings,
         eventSink: RenderFrameEventSink) {
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
        self.starfieldRenderer = pipelines.starfieldRenderer

        self.mapSurfaceGridBuffers = RendererSetup.makeMapSurfaceGridBuffers(metalDevice: metal.device)
        self.flatTileOriginCalculator = FlatTileOriginCalculator(metalDevice: metal.device)
        self.globeCapRenderer = GlobeCapRenderer(metalDevice: metal.device,
                                                 layer: layer,
                                                 library: metal.library,
                                                 maxLatitude: WebMercatorMath.maxLatitudeRadians,
                                                 mapBaseColors: mapBaseColors)
        self.nightLightsTexture = NightLightsTexture(device: metal.device)

        self.textRenderer = TextRenderer(device: metal.device, library: metal.library)
        self.poiSpriteAtlas = PoiSpriteAtlas(device: metal.device)
        self.tilesTexture = GlobeTilesTexture(metalDevice: metal.device, tilePipeline: tilePipeline)
        self.tileRenderStore = TileRenderStore(mapStyle: mapStyle,
                                               metalDevice: metal.device,
                                               textRenderer: textRenderer,
                                               config: config)
        self.tileRenderStore.eventSink = eventSink
        self.baseLabelCache = BaseLabelCache(metalDevice: metal.device)
        self.roadLabelCache = RoadLabelCache(metalDevice: metal.device,
                                             textRenderer: textRenderer)

        self.avatarSource = avatarSource
        self.avatarsRenderer = AvatarsRenderer(metalDevice: metal.device,
                                               layer: layer,
                                               library: metal.library,
                                               config: config.avatars)
        self.debugOverlayRenderer = DebugOverlayRenderer(metalDevice: metal.device, settings: config.debug)
    }

    // MARK: - Settings

    func applySettings(_ settings: ImmersiveMapSettings) {
        debugOverlayRenderer.apply(settings: settings.debug)
    }

    // MARK: - Depth States

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
