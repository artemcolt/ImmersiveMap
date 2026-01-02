//
//  ComputeGloneToScreen.swift
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

import Metal

class ComputeGlobeToScreen {
    let globeComputePipeline: GlobeComputePipeline
    
    private var globeComputeInputBuffer: MTLBuffer
    private var globeComputeOutputBuffer: MTLBuffer
    
    init(_ globeComputePipeline: GlobeComputePipeline, metalDevice: MTLDevice) {
        self.globeComputePipeline = globeComputePipeline
        
        globeComputeInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeTilePointInput>.stride, options: [.storageModeShared]
        )!
        globeComputeOutputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeScreenPointOutput>.stride, options: [.storageModeShared]
        )!
    }
    
    func run(computeEncoder: MTLComputeCommandEncoder, drawSize: CGSize,
             cameraUniform: CameraUniform, globe: Globe,
             commandBuffer: MTLCommandBuffer, screenPoints: ScreenPoints) {
        globeComputePipeline.encode(encoder: computeEncoder)
        
        var input = GlobeTilePointInput(uv: SIMD2<Float>(0.4, 0.4),
                                        tile: SIMD3<Int32>(0, 0, 0))
        globeComputeInputBuffer.contents().copyMemory(from: &input,
                                                      byteCount: MemoryLayout<GlobeTilePointInput>.stride)
        
        var screenParams = GlobeScreenParams(viewportSize: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                                             outputPixels: 1)
        
        var cameraUniform = cameraUniform
        var globe = globe
        computeEncoder.setBuffer(globeComputeInputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(globeComputeOutputBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 2)
        computeEncoder.setBytes(&globe, length: MemoryLayout<Globe>.stride, index: 3)
        computeEncoder.setBytes(&screenParams, length: MemoryLayout<GlobeScreenParams>.stride, index: 4)
        
        let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
        let threadgroupsPerGrid = MTLSize(width: 1, height: 1, depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let pointer = self.globeComputeOutputBuffer.contents().bindMemory(to: GlobeScreenPointOutput.self, capacity: 1)
            let result = pointer.pointee
            if result.visible != 0 {
                print("Compute test (tile 0,0,0): screen=\(result.position), depth=\(result.depth)")
            } else {
                print("Compute test (tile 0,0,0): not visible")
            }
            
            screenPoints.update(result.position)
        }
    }
}
