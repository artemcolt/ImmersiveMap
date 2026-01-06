//
//  GlobeLabelScreenCompute.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class GlobeLabelScreenCompute {
    private let pipeline: GlobeLabelComputePipeline

    init(pipeline: GlobeLabelComputePipeline) {
        self.pipeline = pipeline
    }

    func run(drawSize: CGSize,
             cameraUniform: CameraUniform,
             globe: Globe,
             commandBuffer: MTLCommandBuffer,
             buffers: LabelScreenBuffers,
             collisionCalculator: LabelCollisionCalculator,
             labelStateBuffer: MTLBuffer,
             duplicateFlagsBuffer: MTLBuffer,
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
        var globe = globe
        computeEncoder.setBuffer(buffers.inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(buffers.outputBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 2)
        computeEncoder.setBytes(&globe, length: MemoryLayout<Globe>.stride, index: 3)
        computeEncoder.setBytes(&screenParams, length: MemoryLayout<GlobeScreenParams>.stride, index: 4)

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
            labelStateBuffer: labelStateBuffer,
            duplicateFlagsBuffer: duplicateFlagsBuffer,
            desiredVisibilityBuffer: desiredVisibilityBuffer,
            now: now,
            duration: duration
        )
    }
}
