//
//  Renderer.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import simd
import Metal
import MetalKit
import QuartzCore // Для CAMetalLayer

class Renderer {
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    let vertexBuffer: MTLBuffer
    let parameters: Parameters
    let polygonPipeline: PolygonsPipeline
    let camera: Camera
    let cameraControl: CameraControl
    private let frame: Frame
    
    let vertices: [PolygonsPipeline.Vertex] = [
        // axes
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(1, 0, 0, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(1.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(1, 0, 0, 1)),
        
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(0, 1, 0, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 1.0, 0.0, 1.0),   color: SIMD4<Float>(0, 1, 0, 1)),
        
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(0, 0, 1, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 1.0, 1.0),   color: SIMD4<Float>(0, 0, 1, 1)),
    ]
    
    init(layer: CAMetalLayer) {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal не поддерживается на этом устройстве")
        }
        self.parameters = Parameters()
        self.metalDevice = metalDevice
        layer.device = metalDevice
        layer.pixelFormat = .bgra8Unorm
        
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("Не удалось создать command queue")
        }
        self.commandQueue = queue
        
        // Создаём вершинный буфер
        vertexBuffer = metalDevice.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<PolygonsPipeline.Vertex>.stride, options: [])!
        
        polygonPipeline = PolygonsPipeline(metalDevice: metalDevice, layer: layer)
        
        camera = Camera()
        cameraControl = CameraControl()
        frame = Frame(metalDevice: metalDevice)
    }
    
    func render(to layer: CAMetalLayer) {
        frame.prepare(layer: layer, camera: camera)
        
        if cameraControl.update {
            let yaw = cameraControl.yaw
            let pitch = cameraControl.pitch
            
            let camUp = SIMD3<Float>(0, 1, 0)
            let camDirection = SIMD3<Float>(0, 0, 1)
            let camRight = SIMD3<Float>(1, 0, 0)
            
            let pitchQuat = simd_quatf(angle: pitch, axis: camRight)
            let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 0, 1))
            
            camera.eye = simd_act(yawQuat * pitchQuat, camDirection)
            camera.up = simd_act(yawQuat * pitchQuat, camUp)
            
            camera.recalculateMatrix()
            cameraControl.update = false
        }
        
        guard let frameTexture = frame.msaaTexture else { return }
        guard let drawable = layer.nextDrawable(),
              let cameraMatrix = camera.cameraMatrix else { return }
        
        let clearColor = parameters.clearColor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = frameTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: clearColor.x,
                                                                            green: clearColor.y,
                                                                            blue: clearColor.z,
                                                                            alpha: clearColor.w)
        renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
        renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.texture
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        // camera uniform
        var cameraUniform = CameraUniform(matrix: cameraMatrix)
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        
        polygonPipeline.setPipelineState(renderEncoder: renderEncoder)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
