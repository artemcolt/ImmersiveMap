//
//  TileBuffers.swift
//  TucikMap
//
//  Created by Artem on 7/3/25.
//

import MetalKit


struct TileBuffers {
    let verticesBuffer: MTLBuffer
    let indicesBuffer: MTLBuffer
    let stylesBuffer: MTLBuffer
    let indicesCount: Int
    let verticesCount: Int
    
    // labels
    let tilePointInputs: [TilePointInput]
    let labelsVertices: [LabelVertex]
    let labelsVerticesRanges: [LabelVerticesRange]
    let labelsVerticesBuffer: MTLBuffer?
    let labelsCount: Int
    let labelsVerticesCount: Int
    let labelsMeta: [GlobeLabelMeta]
}

struct LabelVerticesRange {
    let start: Int
    let count: Int
}
