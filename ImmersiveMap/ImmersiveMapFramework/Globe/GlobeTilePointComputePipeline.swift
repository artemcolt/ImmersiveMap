//
//  GlobeTilePointComputePipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 9/20/25.
//

import Metal
import simd

struct TilePointInput {
    var uv: SIMD2<Float>
    var tile: SIMD3<Int32>
    var size: SIMD2<Float>
}

struct ScreenParams {
    var viewportSize: SIMD2<Float>
    var outputPixels: UInt32
    var _padding: UInt32 = 0
}

struct ScreenPointOutput {
    var position: SIMD2<Float>
    var depth: Float
    var visible: UInt32
}

class GlobeTilePointComputePipeline {
    let pipelineState: MTLComputePipelineState
    
    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "globeTilePointToScreenKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }
    
    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
