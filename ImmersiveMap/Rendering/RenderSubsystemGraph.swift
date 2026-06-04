// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class RenderSubsystemGraph {
    let resourceRegistry = RenderResourceRegistry()

    private let registry: RenderSubsystemRegistry
    private weak var baseLabelDrawSubsystem: BaseLabelDrawSubsystem?
    private weak var roadLabelDrawSubsystem: RoadLabelDrawSubsystem?
    private weak var avatarSubsystem: AvatarRenderSubsystem?

    init(context: RenderPersistentContext,
         settings: ImmersiveMapSettings,
         initialZoom: Int,
         buildingWinnerIDTextureProvider: @escaping () -> MTLTexture?) {
        let tileDemandPlacementSubsystem = TileDemandPlacementSubsystem(tileRenderStore: context.tileRenderStore,
                                                                        initialZoom: initialZoom)
        let tileProjectionIndexSubsystem = TileProjectionIndexSubsystem(flatTileOriginCalculator: context.flatTileOriginCalculator)
        let tileGlobeTextureSubsystem = TileGlobeTextureSubsystem(tilesTexture: context.tilesTexture)
        let baseLabelSubsystem = BaseLabelPrepareSubsystem(baseLabelCache: context.baseLabelCache,
                                                           roadLabelCache: context.roadLabelCache,
                                                           metalDevice: context.metalContext.device,
                                                           library: context.metalContext.library,
                                                           settings: settings.labels)
        let baseLabelDrawSubsystem = BaseLabelDrawSubsystem(textRenderer: context.textRenderer,
                                                            poiSpriteAtlas: context.poiSpriteAtlas,
                                                            metalDevice: context.metalContext.device)
        let roadLabelDrawSubsystem = RoadLabelDrawSubsystem(textRenderer: context.textRenderer,
                                                            metalDevice: context.metalContext.device)
        let avatarSubsystem = AvatarRenderSubsystem(avatarsRenderer: context.avatarsRenderer,
                                                    avatarSource: context.avatarSource,
                                                    depthDisabledState: context.depthDisabledState)
        let commonViewSceneSubsystem = CommonViewSceneRenderSubsystem(depthDisabledState: context.depthDisabledState)
        let globeViewSceneSubsystem = GlobeViewSceneRenderSubsystem(starfieldRenderer: context.starfieldRenderer,
                                                                    globeDepthState: context.extrudedDepthState,
                                                                    globeCapDepthState: context.globeCapDepthState,
                                                                    depthDisabledState: context.depthDisabledState,
                                                                    globeCapRenderer: context.globeCapRenderer,
                                                                    globePipeline: context.globePipeline,
                                                                    mapSurfaceGridBuffers: context.mapSurfaceGridBuffers,
                                                                    tilesTexture: context.tilesTexture)
        let flatViewSceneSubsystem = FlatViewSceneRenderSubsystem(tilePipeline: context.tilePipeline,
                                                                  separateRoadRenderingMinimumZoom: settings.style.flatSeparateRoadRenderingMinimumZoom,
                                                                  buildingExtrusionAlpha: settings.style.buildingExtrusionAlpha,
                                                                  buildingWinnerIDTextureProvider: buildingWinnerIDTextureProvider,
                                                                  extrudedTilePipeline: context.extrudedTilePipeline,
                                                                  extrudedColorPassDepthState: context.extrudedColorPassDepthState,
                                                                  depthDisabledState: context.depthDisabledState)
        let debugSubsystem = DebugOverlayRenderSubsystem(polygonPipeline: context.polygonPipeline,
                                                         debugOverlayRenderer: context.debugOverlayRenderer,
                                                         textRenderer: context.textRenderer)

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
