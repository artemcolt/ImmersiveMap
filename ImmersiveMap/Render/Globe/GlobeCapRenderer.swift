// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore
import simd

struct GlobeCapParams {
    var edgeColor: SIMD4<Float>
    var fillColor: SIMD4<Float>
    var blendStartAbsLatitude: Float
    var blendEndAbsLatitude: Float
    var padding = SIMD2<Float>(0, 0)
}

struct GlobeCapPalette {
    var north: GlobeCapParams
    var south: GlobeCapParams
}

final class GlobeCapRenderer {
    private let pipeline: GlobeCapPipeline
    private let northCapBuffers: MapSurfaceGridBuffers
    private let southCapBuffers: MapSurfaceGridBuffers
    private let palette: GlobeCapPalette

    init(metalDevice: MTLDevice,
         layer: CAMetalLayer,
         library: MTLLibrary,
         maxLatitude: Double,
         mapBaseColors: ImmersiveMapBaseColors,
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

        northCapBuffers = MapSurfaceGridBuffers(
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
        southCapBuffers = MapSurfaceGridBuffers(
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

        palette = Self.makePalette(mapBaseColors: mapBaseColors,
                                   maxLatitude: maxLatitude)
    }

    func draw(renderEncoder: MTLRenderCommandEncoder,
              cameraUniform: CameraUniform,
              globe: GlobeUniform) {
        pipeline.selectPipeline(renderEncoder: renderEncoder)
        // Cap winding differs from the globe tile mesh after geographic-latitude
        // alignment, so disabling culling keeps the patch visible on both poles.
        renderEncoder.setCullMode(.none)
        var cameraUniform = cameraUniform
        var globe = globe
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBytes(&globe, length: MemoryLayout<GlobeUniform>.stride, index: 2)
        renderEncoder.setFragmentBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)

        var capParams = palette.north
        renderEncoder.setFragmentBytes(&capParams, length: MemoryLayout<GlobeCapParams>.stride, index: 0)
        renderEncoder.setVertexBuffer(northCapBuffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: northCapBuffers.indicesCount,
                                            indexType: .uint32,
                                            indexBuffer: northCapBuffers.indicesBuffer,
                                            indexBufferOffset: 0)

        capParams = palette.south
        renderEncoder.setFragmentBytes(&capParams, length: MemoryLayout<GlobeCapParams>.stride, index: 0)
        renderEncoder.setVertexBuffer(southCapBuffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: southCapBuffers.indicesCount,
                                            indexType: .uint32,
                                            indexBuffer: southCapBuffers.indicesBuffer,
                                            indexBufferOffset: 0)
    }

    static func makePalette(mapBaseColors: ImmersiveMapBaseColors,
                            maxLatitude: Float,
                            featherDegrees: Float = 6.0) -> GlobeCapPalette {
        let waterColor = mapBaseColors.getWaterColor()
        let tileBackgroundColor = mapBaseColors.getTileBgColor()
        let northPoleColor = mapBaseColors.getNorthPoleColor()
        let southPoleColor = mapBaseColors.getSouthPoleColor()
        let featherRadians = featherDegrees * (.pi / 180.0)
        let fadeEndAbsLatitude = min(Float.pi / 2.0, maxLatitude + featherRadians)
        let northComposite = compositeOpaqueColor(foreground: northPoleColor,
                                                  background: waterColor)
        let southComposite = compositeOpaqueColor(foreground: southPoleColor,
                                                  background: tileBackgroundColor)

        return GlobeCapPalette(
            north: GlobeCapParams(edgeColor: northComposite,
                                  fillColor: northComposite,
                                  blendStartAbsLatitude: maxLatitude,
                                  blendEndAbsLatitude: fadeEndAbsLatitude),
            south: GlobeCapParams(edgeColor: southComposite,
                                  fillColor: southComposite,
                                  blendStartAbsLatitude: maxLatitude,
                                  blendEndAbsLatitude: fadeEndAbsLatitude)
        )
    }

    private static func compositeOpaqueColor(foreground: SIMD4<Float>,
                                             background: SIMD4<Float>) -> SIMD4<Float> {
        let alpha = simd_clamp(foreground.w, 0, 1)
        let rgb = foreground.xyz * alpha + background.xyz * (1 - alpha)
        return SIMD4<Float>(rgb, 1)
    }
}
