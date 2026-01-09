//
//  CometPipeline.swift
//  ImmersiveMap
//
//  Created by Artem on 9/21/25.
//
//  Task Notes
//  - Purpose: pipeline for comet point-sprite rendering (streaks in space view).
//  - Uses comet vertex/fragment shaders from Starfield.metal with additive blending.
//  - Geometry layout matches CometVertex in Starfield.swift.
//  - Behavior: comets originate from the camera direction, move mostly horizontal with a downward
//    bias (always down, never up), and remain camera-facing.

import MetalKit

final class CometPipeline {
    private struct CometVertex {
        let startPosition: SIMD3<Float>
        let endPosition: SIMD3<Float>
        let size: Float
        let brightness: Float
        let startTime: Float
        let duration: Float
    }

    let pipelineState: MTLRenderPipelineState

    init(metalDevice: MTLDevice, layer: CAMetalLayer, library: MTLLibrary) {
        let vertexFunction = library.makeFunction(name: "cometVertexShader")
        let fragmentFunction = library.makeFunction(name: "cometFragmentShader")

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[3].format = .float
        vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<Float>.stride
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.attributes[4].format = .float
        vertexDescriptor.attributes[4].offset = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<Float>.stride * 2
        vertexDescriptor.attributes[4].bufferIndex = 0
        vertexDescriptor.attributes[5].format = .float
        vertexDescriptor.attributes[5].offset = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<Float>.stride * 3
        vertexDescriptor.attributes[5].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<CometVertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create comet pipeline: \(error)")
        }
    }

    func selectPipeline(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(pipelineState)
    }
}
