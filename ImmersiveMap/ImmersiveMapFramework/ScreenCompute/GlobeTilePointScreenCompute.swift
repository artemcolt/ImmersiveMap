//
//  GlobeTilePointScreenCompute.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class GlobeTilePointScreenCompute {
    private let pipeline: GlobeTilePointComputePipeline
    
    init(pipeline: GlobeTilePointComputePipeline) {
        self.pipeline = pipeline
    }
    
    func run(drawSize: CGSize,
             cameraUniform: CameraUniform,
             globe: Globe,
             commandBuffer: MTLCommandBuffer,
             buffers: TilePointScreenBuffers) {
        guard buffers.pointsCount > 0 else {
            return
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        pipeline.encode(encoder: computeEncoder)

        var screenParams = ScreenParams(viewportSize: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)), outputPixels: 1)

        var cameraUniform = cameraUniform
        var globe = globe
        computeEncoder.setBuffer(buffers.inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(buffers.outputBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 2)
        computeEncoder.setBytes(&globe, length: MemoryLayout<Globe>.stride, index: 3)
        computeEncoder.setBytes(&screenParams, length: MemoryLayout<ScreenParams>.stride, index: 4)

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
