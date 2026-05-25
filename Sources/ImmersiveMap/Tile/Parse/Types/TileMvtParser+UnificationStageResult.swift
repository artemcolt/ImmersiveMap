//
//  TileMvtParser+UnificationStageResult.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation

extension TileMvtParser {
    struct UnificationStageResult {
        var drawingPolygon: DrawingPolygonBytes
        var drawingRoadPhases: RoadStructureBuckets<RoadGeometryPhases<DrawingGeometryLayer>>
        var drawingBridgePolygon: DrawingPolygonBytes
        var drawingExtruded: DrawingExtrudedBytes
        var styles: [TilePolygonStyle]
        var overviewStyleMasks: [Float]
        var bridgeStyles: [TilePolygonStyle]
        var bridgeOverviewStyleMasks: [Float]
    }
}
