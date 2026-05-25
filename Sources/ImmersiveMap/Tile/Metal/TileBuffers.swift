//
//  TileBuffers.swift
//  TucikMap
//
//  Created by Artem on 7/3/25.
//

import MetalKit

struct LabelsByStyleRun {
    let style: LabelTextStyle
    let localGlyphVerticesBuffer: MTLBuffer?
    let localGlyphVertexCount: Int
}

struct PoiIconRunBuffer {
    let style: LabelTextStyle
    let localVerticesBuffer: MTLBuffer?
    let localVertexCount: Int
}

struct TextLabelPlacementInput {
    let pointInput: TilePointInput
    let placementMeta: LabelPlacementMeta
}

struct TileBuffers {
    struct GeometryLayer {
        let verticesBuffer: MTLBuffer
        let indicesBuffer: MTLBuffer
        let stylesBuffer: MTLBuffer
        let overviewStyleMaskBuffer: MTLBuffer
        let indicesCount: Int
        let verticesCount: Int
    }

    struct Extruded {
        let verticesBuffer: MTLBuffer
        let indicesBuffer: MTLBuffer
        let stylesBuffer: MTLBuffer
        let indicesCount: Int
        let verticesCount: Int
    }

    struct TextLabels {
        let placementInputs: [TextLabelPlacementInput]
        let labelsByStyleRuns: [LabelsByStyleRun]
        let poiIconRuns: [PoiIconRunBuffer]

        var labelsCount: Int {
            placementInputs.count
        }
    }

    struct RoadLabels {
        let pathInputs: [TilePointInput]
        let pathRanges: [RoadPathRange]
        let pathLabels: [RoadPathLabel]
        let labelStyle: LabelTextStyle?
        let localGlyphVerticesBuffer: MTLBuffer?
        let localGlyphVertexCount: Int
        let glyphBounds: [SIMD4<Float>]
        let glyphBoundRanges: [LabelGlyphRange]
        let sizes: [SIMD2<Float>]
        let anchorRanges: [RoadLabelAnchorRange]
        let anchors: [RoadLabelAnchor]
    }

    let ground: GeometryLayer
    let roads: RoadStructureBuckets<RoadGeometryPhases<GeometryLayer>>
    let bridgeOverlay: GeometryLayer
    let extruded: Extruded
    let textLabels: TextLabels
    let roadLabels: RoadLabels
}

struct LabelGlyphRange {
    let start: Int
    let count: Int
}
