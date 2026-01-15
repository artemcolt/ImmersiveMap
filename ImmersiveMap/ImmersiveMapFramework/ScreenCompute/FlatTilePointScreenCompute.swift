//
//  FlatTilePointScreenCompute.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class FlatTilePointScreenCompute {
    private let pipeline: FlatTilePointComputePipeline

    init(pipeline: FlatTilePointComputePipeline) {
        self.pipeline = pipeline
    }

    func run(drawSize: CGSize,
             cameraUniform: CameraUniform,
             tileOriginDataBuffer: MTLBuffer,
             commandBuffer: MTLCommandBuffer,
             buffers: TilePointScreenBuffers) {
        guard buffers.pointsCount > 0 else {
            return
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        pipeline.encode(encoder: computeEncoder)

        var screenParams = ScreenParams(viewportSize: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                                             outputPixels: 1)

        var cameraUniform = cameraUniform
        computeEncoder.setBuffer(buffers.inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(buffers.outputBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 2)
        computeEncoder.setBytes(&screenParams, length: MemoryLayout<ScreenParams>.stride, index: 3)
        computeEncoder.setBuffer(tileOriginDataBuffer, offset: 0, index: 4)
        computeEncoder.setBuffer(buffers.tileIndexBuffer, offset: 0, index: 5)

        let computeThreadsPerThreadgroup = MTLSize(width: max(1, pipeline.pipelineState.threadExecutionWidth),
                                                   height: 1,
                                                   depth: 1)
        let computeThreadgroupsPerGrid = MTLSize(width: (buffers.pointsCount + computeThreadsPerThreadgroup.width - 1) / computeThreadsPerThreadgroup.width,
                                                 height: 1,
                                                 depth: 1)
        computeEncoder.dispatchThreadgroups(computeThreadgroupsPerGrid, threadsPerThreadgroup: computeThreadsPerThreadgroup)
        computeEncoder.endEncoding()
    }
}
