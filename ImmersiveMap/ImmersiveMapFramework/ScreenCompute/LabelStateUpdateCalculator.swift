//
//  LabelStateUpdateCalculator.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class LabelStateUpdateCalculator {
    private let pipeline: LabelStateUpdatePipeline

    struct LabelStateUpdateParams {
        var count: UInt32
        var now: Float
        var duration: Float
        var _padding: UInt32 = 0
    }

    init(pipeline: LabelStateUpdatePipeline) {
        self.pipeline = pipeline
    }

    func run(commandBuffer: MTLCommandBuffer,
             inputsCount: Int,
             visibilityBuffer: MTLBuffer,
             labelRuntimeBuffer: MTLBuffer,
             now: Float,
             duration: Float) {
        guard inputsCount > 0 else {
            return
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        pipeline.encode(encoder: encoder)
        var params = LabelStateUpdateParams(count: UInt32(inputsCount), now: now, duration: duration)

        encoder.setBuffer(visibilityBuffer, offset: 0, index: 0)
        encoder.setBuffer(labelRuntimeBuffer, offset: 0, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<LabelStateUpdateParams>.stride, index: 2)

        let threadsPerThreadgroup = MTLSize(
            width: max(1, pipeline.pipelineState.threadExecutionWidth),
            height: 1,
            depth: 1
        )
        let threadgroupsPerGrid = MTLSize(
            width: (inputsCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
}
