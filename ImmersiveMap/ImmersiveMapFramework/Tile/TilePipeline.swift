//
//  TilePipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 9/6/25.
//

import MetalKit

class TilePipeline {
    let pipelineState: MTLRenderPipelineState
    
    struct VertexIn {
        let position: SIMD2<Int16>
        let styleIndex: simd_uchar1
    }
    
    init(metalDevice: MTLDevice, layer: CAMetalLayer, library: MTLLibrary) {
        let vertexFunction = library.makeFunction(name: "tileVertexShader")
        let fragmentFunction = library.makeFunction(name: "tileFragmentShader")
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .short2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .uchar
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Int16>>.size
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexIn>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
//        pipelineDescriptor.rasterSampleCount = 4
        
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        self.pipelineState = try! metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    func selectPipeline(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(pipelineState)
    }
}
