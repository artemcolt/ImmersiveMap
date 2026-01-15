//
//  Renderer+DebugOverlay.swift
//  ImmersiveMap
//
//  Created by Artem on 1/10/26.
//

import Foundation
import simd
import Metal
import MetalKit

extension Renderer {
    func drawDebugOverlay(renderEncoder: MTLRenderCommandEncoder,
                          screenMatrix: matrix_float4x4,
                          drawSize: CGSize,
                          viewMode: ViewMode,
                          cameraUniform: CameraUniform) {
        debugOverlayRenderer.drawAxes(renderEncoder: renderEncoder,
                                      polygonPipeline: polygonPipeline,
                                      cameraUniform: cameraUniform)
        
        for point in camera.testPoints {
            let verticesTest = [PolygonsPipeline.Vertex(position: point, color: SIMD4<Float>(1, 0, 0, 1))]
            renderEncoder.setVertexBytes(verticesTest,
                                         length: MemoryLayout<PolygonsPipeline.Vertex>.stride * verticesTest.count,
                                         index: 0)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: verticesTest.count)
        }
        camera.testPoints = []
        
        var matrix = screenMatrix
        renderEncoder.setVertexBytes(&matrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        for screenPoint in screenPoints.get() {
            let simd4 = SIMD4<Float>(screenPoint.x, screenPoint.y, 0, 1)
            let verticesTest = [PolygonsPipeline.Vertex(position: simd4, color: SIMD4<Float>(1, 0, 0, 1))]
            let len = MemoryLayout<PolygonsPipeline.Vertex>.stride * verticesTest.count
            renderEncoder.setVertexBytes(verticesTest, length: len, index: 0)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: verticesTest.count)
        }
        
        debugOverlayRenderer.drawZoomText(renderEncoder: renderEncoder,
                                          textRenderer: textRenderer,
                                          screenMatrix: screenMatrix,
                                          drawSize: drawSize,
                                          zoom: cameraControl.zoom)
        let latLon = cameraControl.getLatLonDeg(viewMode: viewMode)
        debugOverlayRenderer.drawLatLonText(renderEncoder: renderEncoder,
                                            textRenderer: textRenderer,
                                            screenMatrix: screenMatrix,
                                            drawSize: drawSize,
                                            latitude: latLon.latDeg,
                                            longitude: latLon.lonDeg)
    }
}
