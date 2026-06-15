// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

enum RenderGraphFactory {
    static func makeDefaultGraph(context: RenderPersistentContext,
                                 settings: ImmersiveMapSettings,
                                 initialZoom: Int,
                                 buildingWinnerIDTextureProvider: @escaping () -> MTLTexture?) -> RenderGraph {
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
        let buildingWinnerSubsystem = BuildingWinnerRenderSubsystem(extrudedTilePipeline: context.extrudedTilePipeline,
                                                                    extrudedDepthState: context.extrudedDepthState)
        let flatMapSurfaceSubsystem = FlatMapSurfaceRenderSubsystem(tilePipeline: context.tilePipeline,
                                                                    separateRoadRenderingMinimumZoom: settings.style.flatSeparateRoadRenderingMinimumZoom)
        let buildingExtrusionSubsystem = BuildingExtrusionRenderSubsystem(buildingExtrusionAlpha: settings.style.buildingExtrusionAlpha,
                                                                          buildingWinnerIDTextureProvider: buildingWinnerIDTextureProvider,
                                                                          extrudedTilePipeline: context.extrudedTilePipeline,
                                                                          extrudedColorPassDepthState: context.extrudedColorPassDepthState,
                                                                          depthDisabledState: context.depthDisabledState)
        let starfieldSubsystem = StarfieldRenderSubsystem(starfieldRenderer: context.starfieldRenderer)
        let globeSurfaceSubsystem = GlobeSurfaceRenderSubsystem(globeDepthState: context.extrudedDepthState,
                                                                globePipeline: context.globePipeline,
                                                                mapSurfaceGridBuffers: context.mapSurfaceGridBuffers,
                                                                nightLightsTexture: context.nightLightsTexture,
                                                                tilesTexture: context.tilesTexture)
        let globeCapSubsystem = GlobeCapRenderSubsystem(globeCapDepthState: context.globeCapDepthState,
                                                        depthDisabledState: context.depthDisabledState,
                                                        globeCapRenderer: context.globeCapRenderer,
                                                        nightLightsTexture: context.nightLightsTexture,
                                                        tilesTexture: context.tilesTexture)
        let debugSubsystem = DebugOverlayRenderSubsystem(polygonPipeline: context.polygonPipeline,
                                                         debugOverlayRenderer: context.debugOverlayRenderer,
                                                         textRenderer: context.textRenderer)

        let subsystems: [any RenderSubsystem] = [
            tileDemandPlacementSubsystem,
            tileProjectionIndexSubsystem,
            tileGlobeTextureSubsystem,
            baseLabelSubsystem,
            baseLabelDrawSubsystem,
            roadLabelDrawSubsystem,
            avatarSubsystem,
            buildingWinnerSubsystem,
            flatMapSurfaceSubsystem,
            buildingExtrusionSubsystem,
            starfieldSubsystem,
            globeSurfaceSubsystem,
            globeCapSubsystem,
            debugSubsystem
        ]
        let availabilityProviders: [any RenderPassAvailabilityProvider] = [
            baseLabelDrawSubsystem,
            roadLabelDrawSubsystem,
            avatarSubsystem,
            debugSubsystem
        ]
        return RenderGraph(registry: RenderSubsystemRegistry(subsystems: subsystems),
                           availabilityProviders: availabilityProviders)
    }
}
