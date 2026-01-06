//
//  ComputeGlobeLabelToScreen.swift
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

import Metal
import simd

class ComputeGlobeLabelToScreen {
    let globeComputePipeline: GlobeLabelComputePipeline
    let flatComputePipeline: FlatLabelComputePipeline
    let labelCollisionCalculator: LabelCollisionCalculator
    
    private let metalDevice: MTLDevice
    var globeComputeInputBuffer: MTLBuffer
    var globeComputeOutputBuffer: MTLBuffer
    private var inputsCount: Int = 0
    
    var labelCollisionOutputBuffer: MTLBuffer {
        labelCollisionCalculator.outputBuffer
    }
    
    init(_ globeComputePipeline: GlobeLabelComputePipeline,
         _ flatComputePipeline: FlatLabelComputePipeline,
         _ labelCollisionCalculator: LabelCollisionCalculator,
         metalDevice: MTLDevice) {
        self.globeComputePipeline = globeComputePipeline
        self.flatComputePipeline = flatComputePipeline
        self.labelCollisionCalculator = labelCollisionCalculator
        self.metalDevice = metalDevice
        
        globeComputeInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeLabelInput>.stride, options: [.storageModeShared]
        )!
        globeComputeOutputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeScreenPointOutput>.stride, options: [.storageModeShared]
        )!
    }
    
    private func ensureBuffersCapacity(count: Int) {
        let inputNeeded = count * MemoryLayout<GlobeLabelInput>.stride
        if globeComputeInputBuffer.length < inputNeeded {
            globeComputeInputBuffer = metalDevice.makeBuffer(length: inputNeeded, options: [.storageModeShared])!
        }
        
        let outputNeeded = count * MemoryLayout<GlobeScreenPointOutput>.stride
        if globeComputeOutputBuffer.length < outputNeeded {
            globeComputeOutputBuffer = metalDevice.makeBuffer(length: outputNeeded, options: [.storageModeShared])!
        }
        
        labelCollisionCalculator.ensureOutputCapacity(count: count)
    }
    
    // копируем в буффер информацию только когда необходимо для оптимизации
    func copyDataToBuffer(inputs: [GlobeLabelInput]) {
        ensureBuffersCapacity(count: inputs.count)
        let inputBytes = inputs.count * MemoryLayout<GlobeLabelInput>.stride
        inputs.withUnsafeBytes { bytes in
            globeComputeInputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: inputBytes)
        }
        inputsCount = inputs.count
    }
    
    func runGlobe(drawSize: CGSize,
                  cameraUniform: CameraUniform,
                  globe: Globe,
                  commandBuffer: MTLCommandBuffer,
                  screenPoints: ScreenPoints,
                  labelStateBuffer: MTLBuffer,
                  duplicateFlagsBuffer: MTLBuffer,
                  desiredVisibilityBuffer: MTLBuffer,
                  now: Float,
                  duration: Float) {
        guard inputsCount > 0 else {
            return
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        globeComputePipeline.encode(encoder: computeEncoder)
        
        var screenParams = GlobeScreenParams(viewportSize: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                                             outputPixels: 1)
        
        var cameraUniform = cameraUniform
        var globe = globe
        computeEncoder.setBuffer(globeComputeInputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(globeComputeOutputBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 2)
        computeEncoder.setBytes(&globe, length: MemoryLayout<Globe>.stride, index: 3)
        computeEncoder.setBytes(&screenParams, length: MemoryLayout<GlobeScreenParams>.stride, index: 4)
        
        let computeThreadsPerThreadgroup = MTLSize(width: max(1, globeComputePipeline.pipelineState.threadExecutionWidth),
                                                   height: 1,
                                                   depth: 1)
        let computeThreadgroupsPerGrid = MTLSize(width: (inputsCount + computeThreadsPerThreadgroup.width - 1) / computeThreadsPerThreadgroup.width,
                                                 height: 1,
                                                 depth: 1)
        computeEncoder.dispatchThreadgroups(computeThreadgroupsPerGrid, threadsPerThreadgroup: computeThreadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        // Рассчитываем коллизии текстовых меток на экране
        labelCollisionCalculator.run(
            commandBuffer: commandBuffer,
            inputsCount: inputsCount,
            screenPointsBuffer: globeComputeOutputBuffer,
            inputsBuffer: globeComputeInputBuffer,
            labelStateBuffer: labelStateBuffer,
            duplicateFlagsBuffer: duplicateFlagsBuffer,
            desiredVisibilityBuffer: desiredVisibilityBuffer,
            now: now,
            duration: duration
        )
    }

    func runFlat(drawSize: CGSize,
                 cameraUniform: CameraUniform,
                 tileOriginDataBuffer: MTLBuffer,
                 labelTileIndicesBuffer: MTLBuffer,
                 commandBuffer: MTLCommandBuffer,
                 screenPoints: ScreenPoints,
                 labelStateBuffer: MTLBuffer,
                 duplicateFlagsBuffer: MTLBuffer,
                 desiredVisibilityBuffer: MTLBuffer,
                 now: Float,
                 duration: Float) {
        guard inputsCount > 0 else {
            return
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        flatComputePipeline.encode(encoder: computeEncoder)

        var screenParams = GlobeScreenParams(viewportSize: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                                             outputPixels: 1)

        var cameraUniform = cameraUniform
        computeEncoder.setBuffer(globeComputeInputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(globeComputeOutputBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 2)
        computeEncoder.setBytes(&screenParams, length: MemoryLayout<GlobeScreenParams>.stride, index: 3)
        computeEncoder.setBuffer(tileOriginDataBuffer, offset: 0, index: 4)
        computeEncoder.setBuffer(labelTileIndicesBuffer, offset: 0, index: 5)

        let computeThreadsPerThreadgroup = MTLSize(width: max(1, flatComputePipeline.pipelineState.threadExecutionWidth),
                                                   height: 1,
                                                   depth: 1)
        let computeThreadgroupsPerGrid = MTLSize(width: (inputsCount + computeThreadsPerThreadgroup.width - 1) / computeThreadsPerThreadgroup.width,
                                                 height: 1,
                                                 depth: 1)
        computeEncoder.dispatchThreadgroups(computeThreadgroupsPerGrid, threadsPerThreadgroup: computeThreadsPerThreadgroup)
        computeEncoder.endEncoding()

        labelCollisionCalculator.run(
            commandBuffer: commandBuffer,
            inputsCount: inputsCount,
            screenPointsBuffer: globeComputeOutputBuffer,
            inputsBuffer: globeComputeInputBuffer,
            labelStateBuffer: labelStateBuffer,
            duplicateFlagsBuffer: duplicateFlagsBuffer,
            desiredVisibilityBuffer: desiredVisibilityBuffer,
            now: now,
            duration: duration
        )
    }
}
