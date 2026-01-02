//
//  GlobeCollisionPipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 1/3/26.
//

import Metal

class GlobeCollisionPipeline {
    let pipelineState: MTLComputePipelineState
    
    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "globeLabelCollisionKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }
    
    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
