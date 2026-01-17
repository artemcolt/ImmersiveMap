//
//  RoadLabelCollisionCalculator.swift
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

import Metal

final class RoadLabelCollisionCalculator {
    private let pipeline: RoadLabelCollisionPipeline
    private let metalDevice: MTLDevice
    private(set) var outputBuffer: MTLBuffer

    struct RoadLabelCollisionParams {
        var roadCount: UInt32
        var labelCount: UInt32
        var _padding0: UInt32 = 0
        var _padding1: UInt32 = 0
    }

    init(pipeline: RoadLabelCollisionPipeline, metalDevice: MTLDevice) {
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
             roadCount: Int,
             labelCount: Int,
             roadPointsBuffer: MTLBuffer,
             roadCollisionInputsBuffer: MTLBuffer,
             roadGlyphInputsBuffer: MTLBuffer,
             labelPointsBuffer: MTLBuffer,
             labelCollisionInputsBuffer: MTLBuffer,
             labelVisibilityBuffer: MTLBuffer) {
        guard roadCount > 0 else {
            return
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        ensureOutputCapacity(count: roadCount)
        pipeline.encode(encoder: encoder)
        var params = RoadLabelCollisionParams(roadCount: UInt32(roadCount),
                                              labelCount: UInt32(labelCount))

        encoder.setBuffer(roadPointsBuffer, offset: 0, index: 0)
        encoder.setBuffer(roadCollisionInputsBuffer, offset: 0, index: 1)
        encoder.setBuffer(roadGlyphInputsBuffer, offset: 0, index: 2)
        encoder.setBuffer(labelPointsBuffer, offset: 0, index: 3)
        encoder.setBuffer(labelCollisionInputsBuffer, offset: 0, index: 4)
        encoder.setBuffer(labelVisibilityBuffer, offset: 0, index: 5)
        encoder.setBuffer(outputBuffer, offset: 0, index: 6)
        encoder.setBytes(&params, length: MemoryLayout<RoadLabelCollisionParams>.stride, index: 7)

        let threadsPerThreadgroup = MTLSize(
            width: max(1, pipeline.pipelineState.threadExecutionWidth),
            height: 1,
            depth: 1
        )
        let threadgroupsPerGrid = MTLSize(
            width: (roadCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
}
