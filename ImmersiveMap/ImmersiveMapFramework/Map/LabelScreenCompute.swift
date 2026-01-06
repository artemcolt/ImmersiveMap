//
//  LabelScreenCompute.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class LabelScreenCompute {
    private let buffers: LabelScreenBuffers
    private let globeCompute: GlobeLabelScreenCompute
    private let flatCompute: FlatLabelScreenCompute
    private let labelCollisionCalculator: LabelCollisionCalculator

    var labelCollisionOutputBuffer: MTLBuffer {
        labelCollisionCalculator.outputBuffer
    }

    var labelInputBuffer: MTLBuffer {
        buffers.inputBuffer
    }

    var labelOutputBuffer: MTLBuffer {
        buffers.outputBuffer
    }

    init(globeComputePipeline: GlobeLabelComputePipeline,
         flatComputePipeline: FlatLabelComputePipeline,
         labelCollisionCalculator: LabelCollisionCalculator,
         metalDevice: MTLDevice) {
        self.buffers = LabelScreenBuffers(metalDevice: metalDevice)
        self.globeCompute = GlobeLabelScreenCompute(pipeline: globeComputePipeline)
        self.flatCompute = FlatLabelScreenCompute(pipeline: flatComputePipeline)
        self.labelCollisionCalculator = labelCollisionCalculator
    }

    func copyDataToBuffer(inputs: [GlobeLabelInput]) {
        buffers.copyDataToBuffer(inputs: inputs)
        labelCollisionCalculator.ensureOutputCapacity(count: buffers.inputsCount)
    }

    func runGlobe(drawSize: CGSize,
                  cameraUniform: CameraUniform,
                  globe: Globe,
                  commandBuffer: MTLCommandBuffer,
                  labelRuntimeBuffer: MTLBuffer,
                  now: Float,
                  duration: Float) {
        globeCompute.run(drawSize: drawSize,
                         cameraUniform: cameraUniform,
                         globe: globe,
                         commandBuffer: commandBuffer,
                         buffers: buffers,
                         collisionCalculator: labelCollisionCalculator,
                         labelRuntimeBuffer: labelRuntimeBuffer,
                         now: now,
                         duration: duration)
    }

    func runFlat(drawSize: CGSize,
                 cameraUniform: CameraUniform,
                 tileOriginDataBuffer: MTLBuffer,
                 labelTileIndicesBuffer: MTLBuffer,
                 commandBuffer: MTLCommandBuffer,
                 labelRuntimeBuffer: MTLBuffer,
                 now: Float,
                 duration: Float) {
        flatCompute.run(drawSize: drawSize,
                        cameraUniform: cameraUniform,
                        tileOriginDataBuffer: tileOriginDataBuffer,
                        labelTileIndicesBuffer: labelTileIndicesBuffer,
                        commandBuffer: commandBuffer,
                        buffers: buffers,
                        collisionCalculator: labelCollisionCalculator,
                        labelRuntimeBuffer: labelRuntimeBuffer,
                        now: now,
                        duration: duration)
    }
}
