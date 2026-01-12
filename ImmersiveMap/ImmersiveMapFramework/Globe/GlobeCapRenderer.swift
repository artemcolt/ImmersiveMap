//
//  GlobeCapRenderer.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import Metal
import QuartzCore
import simd

struct GlobeCapParams {
    var baseColor: SIMD4<Float>
    var landColor: SIMD4<Float>
    var useBlend: Float
    var padding = SIMD3<Float>(0, 0, 0)
}

final class GlobeCapRenderer {
    private let pipeline: GlobeCapPipeline
    private let northCapBuffers: GridBuffers
    private let southCapBuffers: GridBuffers
    private let northCapParams: GlobeCapParams
    private let southCapParams: GlobeCapParams

    init(metalDevice: MTLDevice,
         layer: CAMetalLayer,
         library: MTLLibrary,
         maxLatitude: Double,
         mapBaseColors: MapBaseColors,
         stacks: Int = 12,
         slices: Int = 48) {
        pipeline = GlobeCapPipeline(metalDevice: metalDevice, layer: layer, library: library)

        let maxLatitude = Float(maxLatitude)
        let northCap = CapGeometry.createCapGrid(stacks: stacks,
                                                 slices: slices,
                                                 isNorth: true,
                                                 maxLatitude: maxLatitude)
        let southCap = CapGeometry.createCapGrid(stacks: stacks,
                                                 slices: slices,
                                                 isNorth: false,
                                                 maxLatitude: maxLatitude)

        northCapBuffers = GridBuffers(
            verticesBuffer: metalDevice.makeBuffer(
                bytes: northCap.vertices,
                length: MemoryLayout<CapGeometry.Vertex>.stride * northCap.vertices.count
            )!,
            indicesBuffer: metalDevice.makeBuffer(
                bytes: northCap.indices,
                length: MemoryLayout<UInt32>.stride * northCap.indices.count
            )!,
            indicesCount: northCap.indices.count
        )
        southCapBuffers = GridBuffers(
            verticesBuffer: metalDevice.makeBuffer(
                bytes: southCap.vertices,
                length: MemoryLayout<CapGeometry.Vertex>.stride * southCap.vertices.count
            )!,
            indicesBuffer: metalDevice.makeBuffer(
                bytes: southCap.indices,
                length: MemoryLayout<UInt32>.stride * southCap.indices.count
            )!,
            indicesCount: southCap.indices.count
        )

        let waterColor = mapBaseColors.getWaterColor()
        let bgColor = mapBaseColors.getTileBgColor()
        let landColor = mapBaseColors.getLandCoverColor()
        northCapParams = GlobeCapParams(baseColor: bgColor,
                                        landColor: landColor,
                                        useBlend: 1)
        southCapParams = GlobeCapParams(baseColor: waterColor,
                                        landColor: SIMD4<Float>(0, 0, 0, 0),
                                        useBlend: 0)
    }

    func draw(renderEncoder: MTLRenderCommandEncoder,
              cameraUniform: CameraUniform,
              globe: Globe) {
        pipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setCullMode(.front)
        var cameraUniform = cameraUniform
        var globe = globe
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBytes(&globe, length: MemoryLayout<Globe>.stride, index: 2)

        var capParams = northCapParams
        renderEncoder.setFragmentBytes(&capParams, length: MemoryLayout<GlobeCapParams>.stride, index: 0)
        renderEncoder.setVertexBuffer(northCapBuffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: northCapBuffers.indicesCount,
                                            indexType: .uint32,
                                            indexBuffer: northCapBuffers.indicesBuffer,
                                            indexBufferOffset: 0)

        capParams = southCapParams
        renderEncoder.setFragmentBytes(&capParams, length: MemoryLayout<GlobeCapParams>.stride, index: 0)
        renderEncoder.setVertexBuffer(southCapBuffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: southCapBuffers.indicesCount,
                                            indexType: .uint32,
                                            indexBuffer: southCapBuffers.indicesBuffer,
                                            indexBufferOffset: 0)
    }
}
