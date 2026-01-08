//
//  LabelStateUpdatePipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class LabelStateUpdatePipeline {
    let pipelineState: MTLComputePipelineState

    init(metalDevice: MTLDevice, library: MTLLibrary) {
        let kernel = library.makeFunction(name: "labelStateUpdateKernel")
        self.pipelineState = try! metalDevice.makeComputePipelineState(function: kernel!)
    }

    func encode(encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(pipelineState)
    }
}
