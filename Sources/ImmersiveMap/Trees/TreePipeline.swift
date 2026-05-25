//
//  TreePipeline.swift
//  ImmersiveMapFramework
//

import MetalKit

final class TreePipeline {
    struct VertexIn {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
    }

    let pipelineState: MTLRenderPipelineState

    init(metalDevice: MTLDevice, layer: CAMetalLayer, library: MTLLibrary) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "treeVertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "treeFragmentShader")
        descriptor.vertexDescriptor = Self.makeVertexDescriptor()
        descriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float

        pipelineState = try! metalDevice.makeRenderPipelineState(descriptor: descriptor)
    }

    func selectPipeline(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(pipelineState)
    }

    private static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()

        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0

        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0

        descriptor.layouts[0].stride = MemoryLayout<VertexIn>.stride
        descriptor.layouts[0].stepFunction = .perVertex

        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = 0
        descriptor.attributes[2].bufferIndex = 1

        descriptor.attributes[3].format = .float
        descriptor.attributes[3].offset = MemoryLayout<SIMD2<Float>>.stride
        descriptor.attributes[3].bufferIndex = 1

        descriptor.attributes[4].format = .float
        descriptor.attributes[4].offset = MemoryLayout<SIMD2<Float>>.stride + MemoryLayout<Float>.stride
        descriptor.attributes[4].bufferIndex = 1

        descriptor.layouts[1].stride = MemoryLayout<TreeInstanceGPU>.stride
        descriptor.layouts[1].stepFunction = .perInstance

        return descriptor
    }
}

