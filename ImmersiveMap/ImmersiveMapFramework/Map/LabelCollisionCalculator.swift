//
//  LabelCollisionCalculator.swift
//  ImmersiveMap
//
//  Created by Artem on 1/3/26.
//

import Metal
import simd

class LabelCollisionCalculator {
    private let pipeline: LabelCollisionPipeline
    private let metalDevice: MTLDevice
    private(set) var outputBuffer: MTLBuffer

    struct CollisionParams {
        var count: UInt32
        var _padding: SIMD3<UInt32> = SIMD3<UInt32>(0, 0, 0)
    }

    init(pipeline: LabelCollisionPipeline, metalDevice: MTLDevice) {
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
             inputsCount: Int,
             screenPointsBuffer: MTLBuffer,
             inputsBuffer: MTLBuffer) {
        guard inputsCount > 0 else {
            return
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        pipeline.encode(encoder: encoder)
        var params = CollisionParams(count: UInt32(inputsCount))

        encoder.setBuffer(screenPointsBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(inputsBuffer, offset: 0, index: 2)
        encoder.setBytes(&params, length: MemoryLayout<CollisionParams>.stride, index: 3)

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
