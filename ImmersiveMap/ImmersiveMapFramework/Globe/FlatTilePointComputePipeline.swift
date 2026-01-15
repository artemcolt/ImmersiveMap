//
//  FlatTilePointComputePipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 1/4/26.
//

import Metal

class FlatTilePointComputePipeline {
    let pipelineState: MTLComputePipelineState
    
    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "flatTilePointToScreenKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }
    
    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
