//
//  Starfield.swift
//  ImmersiveMap
//
//  Created by Artem on 9/21/25.
//
//  Task Notes
//  - Purpose: render a globe-aligned starfield and occasional comets when globe view is active.
//  - Stars: fixed buffer of unit-sphere positions, rotated by globe pan, drawn with a separate projection
//    to avoid affecting map depth precision. Tuned via MapConfiguration.starfield.
//  - Comets: view-space streaks that move downwards with semi-horizontal drift; projection-only matrix
//    keeps them camera-facing. Tuned via MapConfiguration.comets (speed, count, fade-out).
//  - Space: background clear color configured in MapConfiguration.space.

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

    private struct CometVertex {
        let startPosition: SIMD3<Float>
        let endPosition: SIMD3<Float>
        let size: Float
        let brightness: Float
        let startTime: Float
        let duration: Float
    }

    private struct CometParams {
        let time: Float
        let tailScale: Float
        let radiusScale: Float
        let fadeOutSeconds: Float
    }

    private let pipeline: StarfieldPipeline
    private let cometPipeline: CometPipeline
    private let verticesBuffer: MTLBuffer
    private let verticesCount: Int
    private let config: MapConfiguration.StarfieldConfiguration
    private let cometConfig: MapConfiguration.CometConfiguration
    private let cometsBuffer: MTLBuffer?
    private let cometsCount: Int
    private var cachedAspect: Float?
    private var cachedProjection: matrix_float4x4?
    private var cachedCometAspect: Float?
    private var cachedCometProjection: matrix_float4x4?

    init(metalDevice: MTLDevice,
         layer: CAMetalLayer,
         library: MTLLibrary,
         config: MapConfiguration.StarfieldConfiguration,
         comets: MapConfiguration.CometConfiguration) {
        pipeline = StarfieldPipeline(metalDevice: metalDevice, layer: layer, library: library)
        cometPipeline = CometPipeline(metalDevice: metalDevice, layer: layer, library: library)
        self.config = config
        self.cometConfig = comets

        let stars = Starfield.generateStars(count: config.starCount,
                                            sizeMin: config.sizeMin,
                                            sizeMax: config.sizeMax,
                                            brightnessMin: config.brightnessMin,
                                            brightnessMax: config.brightnessMax)
        verticesCount = stars.count
        verticesBuffer = metalDevice.makeBuffer(bytes: stars,
                                                length: MemoryLayout<StarVertex>.stride * stars.count)!

        if comets.enabled && comets.cometCount > 0 && comets.cycleSeconds > 0 {
            let generatedComets = Starfield.generateComets(count: comets.cometCount,
                                                           durationMin: comets.durationMin,
                                                           durationMax: comets.durationMax,
                                                           sizeMin: comets.sizeMin,
                                                           sizeMax: comets.sizeMax,
                                                           brightnessMin: comets.brightnessMin,
                                                           brightnessMax: comets.brightnessMax,
                                                           cycleSeconds: comets.cycleSeconds)
            cometsCount = generatedComets.count
            cometsBuffer = metalDevice.makeBuffer(bytes: generatedComets,
                                                  length: MemoryLayout<CometVertex>.stride * generatedComets.count)
        } else {
            cometsCount = 0
            cometsBuffer = nil
        }
    }

    func draw(renderEncoder: MTLRenderCommandEncoder,
              globe: Globe,
              cameraView: matrix_float4x4,
              cameraEye: SIMD3<Float>,
              drawSize: CGSize,
              nowTime: Float) {
        let aspect = Float(drawSize.width) / Float(drawSize.height)
        if cachedAspect != aspect || cachedProjection == nil {
            cachedProjection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4,
                                                        aspect: aspect,
                                                        near: config.near,
                                                        far: config.far)
            cachedAspect = aspect
        }
        guard let starProjection = cachedProjection else {
            return
        }
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

        drawComets(renderEncoder: renderEncoder,
                   cameraEye: cameraEye,
                   drawSize: drawSize,
                   nowTime: nowTime)
    }

    private func drawComets(renderEncoder: MTLRenderCommandEncoder,
                            cameraEye: SIMD3<Float>,
                            drawSize: CGSize,
                            nowTime: Float) {
        guard let cometsBuffer, cometsCount > 0 else {
            return
        }

        let aspect = Float(drawSize.width) / Float(drawSize.height)
        if cachedCometAspect != aspect || cachedCometProjection == nil {
            cachedCometProjection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4,
                                                             aspect: aspect,
                                                             near: cometConfig.near,
                                                             far: cometConfig.far)
            cachedCometAspect = aspect
        }
        guard let cometProjection = cachedCometProjection else {
            return
        }

        let timeMod = cometConfig.cycleSeconds > 0 ? nowTime.truncatingRemainder(dividingBy: cometConfig.cycleSeconds) : nowTime
        let cometCameraMatrix = cometProjection
        var cometCameraUniform = CameraUniform(matrix: cometCameraMatrix,
                                               eye: cameraEye,
                                               padding: 0)
        var params = CometParams(time: timeMod,
                                 tailScale: cometConfig.tailScale,
                                 radiusScale: cometConfig.radiusScale,
                                 fadeOutSeconds: cometConfig.fadeOutSeconds)

        cometPipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setVertexBuffer(cometsBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&cometCameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBytes(&params, length: MemoryLayout<CometParams>.stride, index: 2)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: cometsCount)
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

    private static func generateComets(count: Int,
                                       durationMin: Float,
                                       durationMax: Float,
                                       sizeMin: Float,
                                       sizeMax: Float,
                                       brightnessMin: Float,
                                       brightnessMax: Float,
                                       cycleSeconds: Float) -> [CometVertex] {
        var comets: [CometVertex] = []
        comets.reserveCapacity(count)

        for _ in 0..<count {
            let startX = Float.random(in: -1.2...1.2)
            let startY = Float.random(in: 0.15...0.9)
            let startZ = -Float.random(in: 1.5...4.0)
            var dx = Float.random(in: -0.9...0.9)
            if abs(dx) < 0.25 {
                dx = dx < 0 ? -0.25 : 0.25
            }
            let dy = -Float.random(in: 0.25...0.8)
            let endX = startX + dx
            let endY = startY + dy
            let endZ = startZ + Float.random(in: -0.15...0.15)
            let startPosition = SIMD3<Float>(startX, startY, startZ)
            let endPosition = SIMD3<Float>(endX, endY, endZ)
            let size = Float.random(in: sizeMin...sizeMax)
            let brightness = Float.random(in: brightnessMin...brightnessMax)
            let startTime = Float.random(in: 0.0...cycleSeconds)
            let duration = Float.random(in: durationMin...durationMax)
            comets.append(CometVertex(startPosition: startPosition,
                                      endPosition: endPosition,
                                      size: size,
                                      brightness: brightness,
                                      startTime: startTime,
                                      duration: duration))
        }

        return comets
    }
}
