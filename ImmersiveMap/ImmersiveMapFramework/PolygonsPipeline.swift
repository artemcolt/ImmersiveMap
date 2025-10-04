//
//  PolygonsPipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

import MetalKit

class PolygonsPipeline {
    // Вершины треугольника (координаты в NDC: от -1 до 1)
    struct Vertex {
        var position: SIMD4<Float> // x, y, z, w
        var color: SIMD4<Float> // x, y, z, w
    }
    
    let pipelineState: MTLRenderPipelineState
    
    init(metalDevice: MTLDevice, layer: CAMetalLayer, library: MTLLibrary) {
        let vertexFunction = library.makeFunction(name: "polygonVertexShader")!
        let fragmentFunction = library.makeFunction(name: "polygonFragmentShader")!
        
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
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Не удалось создать pipeline: \(error)")
        }
    }
    
    func setPipelineState(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(pipelineState)
    }
}
