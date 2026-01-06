//
//  FlatLabelScreenCompute.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class FlatLabelScreenCompute {
    private let pipeline: FlatLabelComputePipeline

    init(pipeline: FlatLabelComputePipeline) {
        self.pipeline = pipeline
    }

    func run(drawSize: CGSize,
             cameraUniform: CameraUniform,
             tileOriginDataBuffer: MTLBuffer,
             labelTileIndicesBuffer: MTLBuffer,
             commandBuffer: MTLCommandBuffer,
             buffers: LabelScreenBuffers,
             collisionCalculator: LabelCollisionCalculator,
             labelRuntimeBuffer: MTLBuffer,
             desiredVisibilityBuffer: MTLBuffer,
             now: Float,
             duration: Float) {
        guard buffers.inputsCount > 0 else {
            return
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        pipeline.encode(encoder: computeEncoder)

        var screenParams = GlobeScreenParams(viewportSize: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                                             outputPixels: 1)

        var cameraUniform = cameraUniform
        computeEncoder.setBuffer(buffers.inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(buffers.outputBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 2)
        computeEncoder.setBytes(&screenParams, length: MemoryLayout<GlobeScreenParams>.stride, index: 3)
        computeEncoder.setBuffer(tileOriginDataBuffer, offset: 0, index: 4)
        computeEncoder.setBuffer(labelTileIndicesBuffer, offset: 0, index: 5)

        let computeThreadsPerThreadgroup = MTLSize(width: max(1, pipeline.pipelineState.threadExecutionWidth),
                                                   height: 1,
                                                   depth: 1)
        let computeThreadgroupsPerGrid = MTLSize(width: (buffers.inputsCount + computeThreadsPerThreadgroup.width - 1) / computeThreadsPerThreadgroup.width,
                                                 height: 1,
                                                 depth: 1)
        computeEncoder.dispatchThreadgroups(computeThreadgroupsPerGrid, threadsPerThreadgroup: computeThreadsPerThreadgroup)
        computeEncoder.endEncoding()

        collisionCalculator.run(
            commandBuffer: commandBuffer,
            inputsCount: buffers.inputsCount,
            screenPointsBuffer: buffers.outputBuffer,
            inputsBuffer: buffers.inputBuffer,
            labelRuntimeBuffer: labelRuntimeBuffer,
            desiredVisibilityBuffer: desiredVisibilityBuffer,
            now: now,
            duration: duration
        )
    }
}
