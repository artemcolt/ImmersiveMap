//
//  RoadLabelVisibilityCalculator.swift
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

import Metal

final class RoadLabelVisibilityCalculator {
    private let pipeline: RoadLabelVisibilityPipeline
    private let metalDevice: MTLDevice
    private(set) var outputBuffer: MTLBuffer

    init(pipeline: RoadLabelVisibilityPipeline, metalDevice: MTLDevice) {
        self.pipeline = pipeline
        self.metalDevice = metalDevice
        self.outputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: [.storageModeShared]
        )!
    }

    func ensureOutputCapacity(count: Int) {
        let needed = count * MemoryLayout<UInt32>.stride
        if outputBuffer.length < needed {
            outputBuffer = metalDevice.makeBuffer(length: needed, options: [.storageModeShared])!
        }
    }

    func run(commandBuffer: MTLCommandBuffer,
             glyphVisibilityBuffer: MTLBuffer,
             glyphRangesBuffer: MTLBuffer,
             instanceCount: Int) {
        guard instanceCount > 0 else {
            return
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        ensureOutputCapacity(count: instanceCount)
        pipeline.encode(encoder: encoder)
        var count = UInt32(instanceCount)

        encoder.setBuffer(glyphVisibilityBuffer, offset: 0, index: 0)
        encoder.setBuffer(glyphRangesBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 3)

        let threadsPerThreadgroup = MTLSize(
            width: max(1, pipeline.pipelineState.threadExecutionWidth),
            height: 1,
            depth: 1
        )
        let threadgroupsPerGrid = MTLSize(
            width: (instanceCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
}
