//
//  GlobePipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 9/20/25.
//

import MetalKit

class GlobePipeline {
    let pipelineState: MTLRenderPipelineState
    
    init(metalDevice: MTLDevice, layer: CAMetalLayer, library: MTLLibrary) {
        let vertexFunction = library.makeFunction(name: "globeVertexShader")
        let fragmentFunction = library.makeFunction(name: "globeFragmentShader")
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SphereGeometry.Vertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
        
        self.pipelineState = try! metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    func selectPipeline(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(pipelineState)
    }
}

