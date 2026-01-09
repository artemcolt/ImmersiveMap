//
//  Starfield.swift
//  ImmersiveMap
//
//  Created by Artem on 9/21/25.
//

import MetalKit
import simd

final class Starfield {
    private struct StarVertex {
        let position: SIMD3<Float>
        let size: Float
        let brightness: Float
    }

    private struct StarfieldParams {
        let radiusScale: Float
        let padding: SIMD3<Float>
    }

    private let pipeline: StarfieldPipeline
    private let verticesBuffer: MTLBuffer
    private let verticesCount: Int
    private let config: MapConfiguration.StarfieldConfiguration

    init(metalDevice: MTLDevice, layer: CAMetalLayer, library: MTLLibrary, config: MapConfiguration.StarfieldConfiguration) {
        pipeline = StarfieldPipeline(metalDevice: metalDevice, layer: layer, library: library)
        self.config = config

        let stars = Starfield.generateStars(count: config.starCount,
                                            sizeMin: config.sizeMin,
                                            sizeMax: config.sizeMax,
                                            brightnessMin: config.brightnessMin,
                                            brightnessMax: config.brightnessMax)
        verticesCount = stars.count
        verticesBuffer = metalDevice.makeBuffer(bytes: stars,
                                                length: MemoryLayout<StarVertex>.stride * stars.count)!
    }

    func draw(renderEncoder: MTLRenderCommandEncoder,
              globe: Globe,
              cameraView: matrix_float4x4,
              cameraEye: SIMD3<Float>,
              drawSize: CGSize,
              nowTime: Float) {
        let aspect = Float(drawSize.width) / Float(drawSize.height)
        let starProjection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4,
                                                      aspect: aspect,
                                                      near: config.near,
                                                      far: config.far)
        let starCameraMatrix = starProjection * cameraView
        var starCameraUniform = CameraUniform(matrix: starCameraMatrix,
                                              eye: cameraEye,
                                              padding: 0)
        var globeData = globe
        var params = StarfieldParams(radiusScale: config.radiusScale, padding: SIMD3<Float>(repeating: 0))
        var time = nowTime

        pipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setVertexBuffer(verticesBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&starCameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBytes(&globeData, length: MemoryLayout<Globe>.stride, index: 2)
        renderEncoder.setVertexBytes(&params, length: MemoryLayout<StarfieldParams>.stride, index: 3)
        renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: verticesCount)
    }

    private static func generateStars(count: Int,
                                      sizeMin: Float,
                                      sizeMax: Float,
                                      brightnessMin: Float,
                                      brightnessMax: Float) -> [StarVertex] {
        var stars: [StarVertex] = []
        stars.reserveCapacity(count)

        for _ in 0..<count {
            let u = Float.random(in: 0.0...1.0)
            let v = Float.random(in: 0.0...1.0)
            let theta = 2.0 * Float.pi * u
            let z = 2.0 * v - 1.0
            let r = sqrt(max(0.0, 1.0 - z * z))
            let position = SIMD3<Float>(r * cos(theta), r * sin(theta), z)
            let size = Float.random(in: sizeMin...sizeMax)
            let brightness = Float.random(in: brightnessMin...brightnessMax)
            stars.append(StarVertex(position: position, size: size, brightness: brightness))
        }

        return stars
    }
}
