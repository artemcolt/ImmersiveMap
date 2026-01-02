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
    
}
