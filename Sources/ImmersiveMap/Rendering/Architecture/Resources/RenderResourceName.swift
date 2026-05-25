//
//  RenderResourceName.swift
//  ImmersiveMapFramework
//

import Foundation

enum RenderResourceName: String {
    case tileVertexBuffer = "TileVertexBuffer"
    case tileStyleBuffer = "TileStyleBuffer"
    case labelGlyphAtlas = "LabelGlyphAtlas"
    case poiSpriteAtlas = "PoiSpriteAtlas"
    case baseLabelRuntimeBuffer = "BaseLabelRuntimeBuffer"
    case roadLabelRuntimeBuffer = "RoadLabelRuntimeBuffer"
    case depthTexture = "DepthTexture"
    case buildingWinnerIDTexture = "BuildingWinnerIDTexture"
    case buildingWinnerDepthTexture = "BuildingWinnerDepthTexture"
    case tileOriginDataBuffer = "TileOriginDataBuffer"
    case polygonPipeline = "PolygonPipeline"
    case tilePipeline = "TilePipeline"
    case extrudedTilePipeline = "ExtrudedTilePipeline"
    case extrudedTileWinnerPipeline = "ExtrudedTileWinnerPipeline"
    case globePipeline = "GlobePipeline"
}
