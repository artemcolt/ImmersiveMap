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

    struct CollisionParams {
        var halfSize: SIMD2<Float>
        var count: UInt32
        var _padding: UInt32 = 0
    }
    
    init(_ globeComputePipeline: GlobeComputePipeline,
         _ globeCollisionPipeline: GlobeCollisionPipeline,
         metalDevice: MTLDevice) {
        self.globeComputePipeline = globeComputePipeline
        self.globeCollisionPipeline = globeCollisionPipeline
        self.metalDevice = metalDevice
        
        globeComputeInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeTilePointInput>.stride, options: [.storageModeShared]
        )!
        globeComputeOutputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeScreenPointOutput>.stride, options: [.storageModeShared]
        )!
        globeCollisionOutputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt32>.stride, options: [.storageModeShared]
        )!
    }
    
    private func ensureBuffersCapacity(count: Int) {
        let inputNeeded = count * MemoryLayout<GlobeTilePointInput>.stride
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
    
    func run(inputs: [GlobeTilePointInput],
             drawSize: CGSize,
             cameraUniform: CameraUniform,
             globe: Globe,
             commandBuffer: MTLCommandBuffer,
             screenPoints: ScreenPoints) {
        guard inputs.isEmpty == false else {
            screenPoints.set([])
            return
        }
        
        ensureBuffersCapacity(count: inputs.count)
        let inputBytes = inputs.count * MemoryLayout<GlobeTilePointInput>.stride
        inputs.withUnsafeBytes { bytes in
            globeComputeInputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: inputBytes)
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
        let computeThreadgroupsPerGrid = MTLSize(width: (inputs.count + computeThreadsPerThreadgroup.width - 1) / computeThreadsPerThreadgroup.width,
                                                 height: 1,
                                                 depth: 1)
        computeEncoder.dispatchThreadgroups(computeThreadgroupsPerGrid, threadsPerThreadgroup: computeThreadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        guard let collisionEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        globeCollisionPipeline.encode(encoder: collisionEncoder)
        var params = CollisionParams(halfSize: SIMD2<Float>(25.0, 25.0),
                                     count: UInt32(inputs.count))
        
        collisionEncoder.setBuffer(globeComputeOutputBuffer, offset: 0, index: 0)
        collisionEncoder.setBuffer(globeCollisionOutputBuffer, offset: 0, index: 1)
        collisionEncoder.setBytes(&params, length: MemoryLayout<CollisionParams>.stride, index: 2)
        
        let collisionThreadsPerThreadgroup = MTLSize(width: max(1, globeCollisionPipeline.pipelineState.threadExecutionWidth),
                                                     height: 1,
                                                     depth: 1)
        let collisionThreadgroupsPerGrid = MTLSize(
            width: (inputs.count + collisionThreadsPerThreadgroup.width - 1) / collisionThreadsPerThreadgroup.width,
            height: 1,
            depth: 1)
        collisionEncoder.dispatchThreadgroups(collisionThreadgroupsPerGrid, threadsPerThreadgroup: collisionThreadsPerThreadgroup)
        collisionEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let pointsPointer = self.globeComputeOutputBuffer.contents().bindMemory(to: GlobeScreenPointOutput.self,
                                                                                    capacity: inputs.count)
            let visibilityPointer = self.globeCollisionOutputBuffer.contents().bindMemory(to: UInt32.self,
                                                                                           capacity: inputs.count)
            
            var visiblePoints: [SIMD2<Float>] = []
            visiblePoints.reserveCapacity(inputs.count)
            for i in 0..<inputs.count {
                if visibilityPointer[i] == 0 || pointsPointer[i].visible == 0 {
                    continue
                }
                visiblePoints.append(pointsPointer[i].position)
            }
            
            screenPoints.set(visiblePoints)
        }
    }
}
