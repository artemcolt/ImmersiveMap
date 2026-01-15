//
//  DebugOverlayRenderer.swift
//  ImmersiveMap
//
//  Created by Artem on 1/10/26.
//

import Foundation
import Metal
import simd

final class DebugOverlayRenderer {
    private let metalDevice: MTLDevice
    private let axesVertexBuffer: MTLBuffer
    private let axesVerticesCount: Int

    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
        let axesVertices: [PolygonsPipeline.Vertex] = [
            PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0), color: SIMD4<Float>(1, 0, 0, 1)),
            PolygonsPipeline.Vertex(position: SIMD4<Float>(1.0, 0.0, 0.0, 1.0), color: SIMD4<Float>(1, 0, 0, 1)),

            PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0), color: SIMD4<Float>(0, 1, 0, 1)),
            PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 1.0, 0.0, 1.0), color: SIMD4<Float>(0, 1, 0, 1)),

            PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0), color: SIMD4<Float>(0, 0, 1, 1)),
            PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 1.0, 1.0), color: SIMD4<Float>(0, 0, 1, 1)),
        ]
        axesVerticesCount = axesVertices.count
        axesVertexBuffer = metalDevice.makeBuffer(
            bytes: axesVertices,
            length: axesVertices.count * MemoryLayout<PolygonsPipeline.Vertex>.stride,
            options: []
        )!
    }

    func drawAxes(renderEncoder: MTLRenderCommandEncoder,
                  polygonPipeline: PolygonsPipeline,
                  cameraUniform: CameraUniform) {
        polygonPipeline.setPipelineState(renderEncoder: renderEncoder)
        renderEncoder.setVertexBuffer(axesVertexBuffer, offset: 0, index: 0)
        var uniform = cameraUniform
        renderEncoder.setVertexBytes(&uniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: axesVerticesCount)
    }

    func drawZoomText(renderEncoder: MTLRenderCommandEncoder,
                      textRenderer: TextRenderer,
                      screenMatrix: matrix_float4x4,
                      drawSize: CGSize,
                      zoom: Double) {
        let zoomText = TextEntry(text: "z: " + zoom.formatted(.number.precision(.fractionLength(2))),
                                 position: SIMD2<Float>(100, Float(drawSize.height) - 380),
                                 scale: 100)
        let textVertices = textRenderer.collectMultiTextVertices(for: [zoomText])
        var zoomTextColor = SIMD3<Float>(0, 0, 0)
        var matrix = screenMatrix
        renderEncoder.setRenderPipelineState(textRenderer.pipelineState)
        let textVerticesLength = MemoryLayout<TextVertex>.stride * textVertices.count
        if textVerticesLength <= 4096 {
            renderEncoder.setVertexBytes(textVertices, length: textVerticesLength, index: 0)
        } else {
            let buffer = metalDevice.makeBuffer(bytes: textVertices, length: textVerticesLength, options: [])!
            renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
        }
        renderEncoder.setVertexBytes(&matrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setFragmentTexture(textRenderer.texture, index: 0)
        renderEncoder.setFragmentBytes(&zoomTextColor, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textVertices.count)
    }
    
    func drawLatLonText(renderEncoder: MTLRenderCommandEncoder,
                        textRenderer: TextRenderer,
                        screenMatrix: matrix_float4x4,
                        drawSize: CGSize,
                        latitude: Double,
                        longitude: Double) {
        let latString = latitude.formatted(.number.precision(.fractionLength(3)))
        let lonString = longitude.formatted(.number.precision(.fractionLength(3)))
        let text = "lat: \(latString) lon: \(lonString)"
        let latLonText = TextEntry(text: text,
                                   position: SIMD2<Float>(100, Float(drawSize.height) - 300),
                                   scale: 100)
        let textVertices = textRenderer.collectMultiTextVertices(for: [latLonText])
        var textColor = SIMD3<Float>(0, 0, 0)
        var matrix = screenMatrix
        renderEncoder.setRenderPipelineState(textRenderer.pipelineState)
        let textVerticesLength = MemoryLayout<TextVertex>.stride * textVertices.count
        if textVerticesLength <= 4096 {
            renderEncoder.setVertexBytes(textVertices, length: textVerticesLength, index: 0)
        } else {
            let buffer = metalDevice.makeBuffer(bytes: textVertices, length: textVerticesLength, options: [])!
            renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
        }
        renderEncoder.setVertexBytes(&matrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setFragmentTexture(textRenderer.texture, index: 0)
        renderEncoder.setFragmentBytes(&textColor, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textVertices.count)
    }
}
