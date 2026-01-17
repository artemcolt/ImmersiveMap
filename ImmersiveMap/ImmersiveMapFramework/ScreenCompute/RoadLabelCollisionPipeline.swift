//
//  RoadLabelCollisionPipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

import Metal

final class RoadLabelCollisionPipeline {
    let pipelineState: MTLComputePipelineState

    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "roadLabelCollisionKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }

    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
