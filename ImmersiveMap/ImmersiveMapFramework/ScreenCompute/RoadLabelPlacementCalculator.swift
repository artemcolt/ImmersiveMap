//
//  RoadLabelPlacementCalculator.swift
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

import Metal

final class RoadLabelPlacementCalculator {
    private let pipeline: RoadLabelPlacementPipeline

    init(pipeline: RoadLabelPlacementPipeline) {
        self.pipeline = pipeline
    }

    func run(commandBuffer: MTLCommandBuffer,
             pathPointsBuffer: MTLBuffer,
             pathRangesBuffer: MTLBuffer,
             glyphInputsBuffer: MTLBuffer,
             placementsBuffer: MTLBuffer,
             screenPointsBuffer: MTLBuffer,
             glyphCount: Int) {
        guard glyphCount > 0 else {
            return
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        pipeline.encode(encoder: encoder)
        var count = UInt32(glyphCount)

        encoder.setBuffer(pathPointsBuffer, offset: 0, index: 0)
        encoder.setBuffer(pathRangesBuffer, offset: 0, index: 1)
        encoder.setBuffer(glyphInputsBuffer, offset: 0, index: 2)
        encoder.setBuffer(placementsBuffer, offset: 0, index: 3)
        encoder.setBuffer(screenPointsBuffer, offset: 0, index: 4)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 5)

        let threadsPerThreadgroup = MTLSize(
            width: max(1, pipeline.pipelineState.threadExecutionWidth),
            height: 1,
            depth: 1
        )
        let threadgroupsPerGrid = MTLSize(
            width: (glyphCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
}
