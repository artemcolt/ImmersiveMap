//
//  ScreenCollisionPipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class ScreenCollisionPipeline {
    let pipelineState: MTLComputePipelineState

    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "screenCollisionKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }

    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
