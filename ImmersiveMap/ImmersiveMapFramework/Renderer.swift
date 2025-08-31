//
//  Renderer.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import Metal
import QuartzCore // Для CAMetalLayer

class Renderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    
    private var msaaTexture: MTLTexture?
    private var lastDrawableSize: CGSize = .zero
    
    // Вершины треугольника (координаты в NDC: от -1 до 1)
    struct Vertex {
        var position: SIMD4<Float> // x, y, z, w
    }
    
    let vertices: [Vertex] = [
        Vertex(position: SIMD4<Float>(0.0, 0.5, 0.0, 1.0)),  // Верхняя точка
        Vertex(position: SIMD4<Float>(-0.5, -0.5, 0.0, 1.0)), // Левая нижняя
        Vertex(position: SIMD4<Float>(0.5, -0.5, 0.0, 1.0))   // Правая нижняя
    ]
    
    init(layer: CAMetalLayer) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal не поддерживается на этом устройстве")
        }
        self.device = device
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        
        guard let queue = device.makeCommandQueue() else {
            fatalError("Не удалось создать command queue")
        }
        self.commandQueue = queue
        
        // Создаём вершинный буфер
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: [])!
        
        // Шейдеры: Загружаем библиотеку из бандла фреймворка
        let bundle = Bundle(for: Renderer.self)  // Бандл фреймворка (Renderer — класс из фреймворка)
        
        // Шейдеры (vertex и fragment)
        let library = try! device.makeDefaultLibrary(bundle: bundle)
        let vertexFunction = library.makeFunction(name: "vertexShader")!
        let fragmentFunction = library.makeFunction(name: "fragmentShader")!
        
        // Пайплайн
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.rasterSampleCount = 4
        pipelineDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Не удалось создать pipeline: \(error)")
        }
    }
    
    func render(to layer: CAMetalLayer) {
        let currentDrawableSize = layer.drawableSize
        if currentDrawableSize != lastDrawableSize || msaaTexture == nil {
            lastDrawableSize = currentDrawableSize
            
            let msaaTextureDescriptor = MTLTextureDescriptor()
            msaaTextureDescriptor.textureType = .type2DMultisample
            msaaTextureDescriptor.pixelFormat = layer.pixelFormat
            msaaTextureDescriptor.width = Int(currentDrawableSize.width)
            msaaTextureDescriptor.height = Int(currentDrawableSize.height)
            msaaTextureDescriptor.storageMode = .private
            msaaTextureDescriptor.sampleCount = 4
            msaaTextureDescriptor.usage = .renderTarget
            
            // Проверяем на нулевой размер (чтобы избежать ошибок на старте)
            if currentDrawableSize.width > 0 && currentDrawableSize.height > 0 {
                msaaTexture = device.makeTexture(descriptor: msaaTextureDescriptor)
            } else {
                return // Пропускаем рендер, если размер нулевой
            }
        }
        
        
        guard let drawable = layer.nextDrawable() else { return }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = msaaTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // Чёрный фон
        renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
        renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.texture
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
