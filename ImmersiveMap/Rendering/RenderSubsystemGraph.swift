// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class RenderSubsystemGraph {
    let resourceRegistry = RenderResourceRegistry()

    private let registry: RenderSubsystemRegistry
    private weak var baseLabelDrawSubsystem: BaseLabelDrawSubsystem?
    private weak var roadLabelDrawSubsystem: RoadLabelDrawSubsystem?
    private weak var avatarSubsystem: AvatarRenderSubsystem?

    init(resources: RenderStaticResources,
         settings: ImmersiveMapSettings,
         initialZoom: Int,
         buildingWinnerIDTextureProvider: @escaping () -> MTLTexture?) {
        let tileDemandPlacementSubsystem = TileDemandPlacementSubsystem(tileRenderStore: resources.tileRenderStore,
                                                                        initialZoom: initialZoom)
        let tileProjectionIndexSubsystem = TileProjectionIndexSubsystem(flatTileOriginCalculator: resources.flatTileOriginCalculator)
        let tileGlobeTextureSubsystem = TileGlobeTextureSubsystem(tilesTexture: resources.tilesTexture)
        let baseLabelSubsystem = BaseLabelPrepareSubsystem(baseLabelCache: resources.baseLabelCache,
                                                           roadLabelCache: resources.roadLabelCache,
                                                           metalDevice: resources.metalContext.device,
                                                           library: resources.metalContext.library,
                                                           settings: settings.labels)
        let baseLabelDrawSubsystem = BaseLabelDrawSubsystem(textRenderer: resources.textRenderer,
                                                            poiSpriteAtlas: resources.poiSpriteAtlas,
                                                            metalDevice: resources.metalContext.device)
        let roadLabelDrawSubsystem = RoadLabelDrawSubsystem(textRenderer: resources.textRenderer,
                                                            metalDevice: resources.metalContext.device)
        let avatarSubsystem = AvatarRenderSubsystem(avatarsRenderer: resources.avatarsRenderer,
                                                    avatarsControllerProvider: resources.avatarsControllerProvider,
                                                    depthDisabledState: resources.depthDisabledState)
        let commonViewSceneSubsystem = CommonViewSceneRenderSubsystem(depthDisabledState: resources.depthDisabledState)
        let globeViewSceneSubsystem = GlobeViewSceneRenderSubsystem(starfield: resources.starfield,
                                                                    globeDepthState: resources.extrudedDepthState,
                                                                    globeCapDepthState: resources.globeCapDepthState,
                                                                    depthDisabledState: resources.depthDisabledState,
                                                                    globeCapRenderer: resources.globeCapRenderer,
                                                                    globePipeline: resources.globePipeline,
                                                                    baseGridBuffers: resources.baseGridBuffers,
                                                                    tilesTexture: resources.tilesTexture)
        let flatViewSceneSubsystem = FlatViewSceneRenderSubsystem(tilePipeline: resources.tilePipeline,
                                                                  separateRoadRenderingMinimumZoom: settings.style.flatSeparateRoadRenderingMinimumZoom,
                                                                  buildingExtrusionAlpha: settings.style.buildingExtrusionAlpha,
                                                                  buildingWinnerIDTextureProvider: buildingWinnerIDTextureProvider,
                                                                  extrudedTilePipeline: resources.extrudedTilePipeline,
                                                                  extrudedColorPassDepthState: resources.extrudedColorPassDepthState,
                                                                  depthDisabledState: resources.depthDisabledState)
        let debugSubsystem = DebugOverlayRenderSubsystem(polygonPipeline: resources.polygonPipeline,
                                                         debugOverlayRenderer: resources.debugOverlayRenderer,
                                                         textRenderer: resources.textRenderer)

        self.baseLabelDrawSubsystem = baseLabelDrawSubsystem
        self.roadLabelDrawSubsystem = roadLabelDrawSubsystem
        self.avatarSubsystem = avatarSubsystem
        self.registry = RenderSubsystemRegistry(subsystems: [tileDemandPlacementSubsystem,
                                                             tileProjectionIndexSubsystem,
                                                             tileGlobeTextureSubsystem,
                                                             baseLabelSubsystem,
                                                             baseLabelDrawSubsystem,
                                                             roadLabelDrawSubsystem,
                                                             avatarSubsystem,
                                                             commonViewSceneSubsystem,
                                                             globeViewSceneSubsystem,
                                                             flatViewSceneSubsystem,
                                                             debugSubsystem])
    }

    var passAvailability: RenderPassAvailability {
        let hasBaseLabels = baseLabelDrawSubsystem?.hasRenderableLabels ?? false
        let hasRoadLabels = roadLabelDrawSubsystem?.hasRenderableLabels ?? false
        return RenderPassAvailability(labelsEnabled: hasBaseLabels || hasRoadLabels,
                                      avatarsEnabled: avatarSubsystem?.hasRenderableAvatars ?? false,
                                      debugOverlayEnabled: false)
    }

    func update(frameContext: FrameContext) {
        registry.update(frameContext: frameContext)
    }

    func prepareGPU(frameContext: FrameContext) {
        registry.prepareGPU(frameContext: frameContext, resourceRegistry: resourceRegistry)
    }

    func encode(pass: RenderPass,
                encoder: MTLRenderCommandEncoder,
                frameContext: FrameContext) {
        registry.encode(pass: pass,
                        encoder: encoder,
                        frameContext: frameContext)
    }

    func handleMemoryWarning() {
        registry.handleMemoryWarning()
    }
}
