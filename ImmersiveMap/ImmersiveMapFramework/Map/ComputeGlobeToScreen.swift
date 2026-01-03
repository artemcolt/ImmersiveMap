//
//  ComputeGloneToScreen.swift
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

import Metal
import simd

class ComputeGlobeToScreen {
    let globeComputePipeline: GlobeComputePipeline
    let globeCollisionPipeline: GlobeCollisionPipeline
    
    private let metalDevice: MTLDevice
    var globeComputeInputBuffer: MTLBuffer
    var globeComputeOutputBuffer: MTLBuffer
    var globeCollisionOutputBuffer: MTLBuffer
    private var inputsCount: Int = 0

    struct CollisionParams {
        var count: UInt32
        var _padding: SIMD3<UInt32> = SIMD3<UInt32>(0, 0, 0)
    }
    
    init(_ globeComputePipeline: GlobeComputePipeline,
         _ globeCollisionPipeline: GlobeCollisionPipeline,
         metalDevice: MTLDevice) {
        self.globeComputePipeline = globeComputePipeline
        self.globeCollisionPipeline = globeCollisionPipeline
        self.metalDevice = metalDevice
        
        globeComputeInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeLabelInput>.stride, options: [.storageModeShared]
        )!
        globeComputeOutputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeScreenPointOutput>.stride, options: [.storageModeShared]
        )!
        globeCollisionOutputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt32>.stride, options: [.storageModeShared]
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
        
        let collisionNeeded = count * MemoryLayout<UInt32>.stride
        if globeCollisionOutputBuffer.length < collisionNeeded {
            globeCollisionOutputBuffer = metalDevice.makeBuffer(length: collisionNeeded, options: [.storageModeShared])!
        }
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
    
    func run(drawSize: CGSize,
             cameraUniform: CameraUniform,
             globe: Globe,
             commandBuffer: MTLCommandBuffer,
             screenPoints: ScreenPoints) {
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
        
        guard let collisionEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        globeCollisionPipeline.encode(encoder: collisionEncoder)
        var params = CollisionParams(count: UInt32(inputsCount))

        
        collisionEncoder.setBuffer(globeComputeOutputBuffer, offset: 0, index: 0)
        collisionEncoder.setBuffer(globeCollisionOutputBuffer, offset: 0, index: 1)
        collisionEncoder.setBuffer(globeComputeInputBuffer, offset: 0, index: 2)
        collisionEncoder.setBytes(&params, length: MemoryLayout<CollisionParams>.stride, index: 3)
        
        let collisionThreadsPerThreadgroup = MTLSize(width: max(1, globeCollisionPipeline.pipelineState.threadExecutionWidth),
                                                     height: 1,
                                                     depth: 1)
        let collisionThreadgroupsPerGrid = MTLSize(
            width: (inputsCount + collisionThreadsPerThreadgroup.width - 1) / collisionThreadsPerThreadgroup.width,
            height: 1,
            depth: 1)
        collisionEncoder.dispatchThreadgroups(collisionThreadgroupsPerGrid, threadsPerThreadgroup: collisionThreadsPerThreadgroup)
        collisionEncoder.endEncoding()
    }
}
