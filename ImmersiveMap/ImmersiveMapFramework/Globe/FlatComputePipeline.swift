//
//  FlatComputePipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 1/4/26.
//

import Metal

class FlatComputePipeline {
    let pipelineState: MTLComputePipelineState
    
    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "flatTileToScreenKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }
    
    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
