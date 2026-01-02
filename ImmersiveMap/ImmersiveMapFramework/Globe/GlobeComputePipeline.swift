//
//  GlobeComputePipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 9/20/25.
//

import Metal
import simd

struct GlobeTilePointInput {
    var uv: SIMD2<Float>
    var tile: SIMD3<Int32>
}

struct GlobeScreenParams {
    var viewportSize: SIMD2<Float>
    var outputPixels: UInt32
    var _padding: UInt32 = 0
}

struct GlobeScreenPointOutput {
    var position: SIMD2<Float>
    var depth: Float
    var visible: UInt32
}

class GlobeComputePipeline {
    let pipelineState: MTLComputePipelineState
    
    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "globeTileToScreenKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }
    
    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
