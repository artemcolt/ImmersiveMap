//
//  TilePointScreenCompute.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class TilePointScreenCompute {
    private let buffers: TilePointScreenBuffers
    private let globeCompute: GlobeTilePointScreenCompute
    private let flatCompute: FlatTilePointScreenCompute

    var pointInputBuffer: MTLBuffer {
        buffers.inputBuffer
    }

    var pointOutputBuffer: MTLBuffer {
        buffers.outputBuffer
    }

    var pointsCount: Int {
        buffers.pointsCount
    }

    init(globeComputePipeline: GlobeTilePointComputePipeline,
         flatComputePipeline: FlatTilePointComputePipeline,
         metalDevice: MTLDevice) {
        self.buffers = TilePointScreenBuffers(metalDevice: metalDevice)
        self.globeCompute = GlobeTilePointScreenCompute(pipeline: globeComputePipeline)
        self.flatCompute = FlatTilePointScreenCompute(pipeline: flatComputePipeline)
    }

    func copyDataToBuffer(inputs: [TilePointInput], tileIndices: [UInt32]) {
        buffers.copyDataToBuffer(inputs: inputs, tileIndices: tileIndices)
    }

    func runGlobe(drawSize: CGSize,
                  cameraUniform: CameraUniform,
                  globe: Globe,
                  commandBuffer: MTLCommandBuffer) {
        globeCompute.run(drawSize: drawSize,
                         cameraUniform: cameraUniform,
                         globe: globe,
                         commandBuffer: commandBuffer,
                         buffers: buffers)
    }

    func runFlat(drawSize: CGSize,
                 cameraUniform: CameraUniform,
                 tileOriginDataBuffer: MTLBuffer,
                 commandBuffer: MTLCommandBuffer) {
        flatCompute.run(drawSize: drawSize,
                        cameraUniform: cameraUniform,
                        tileOriginDataBuffer: tileOriginDataBuffer,
                        commandBuffer: commandBuffer,
                        buffers: buffers)
    }
}
