// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  TilePointScreenProjector.swift
//  ImmersiveMap
//

import simd

struct TilePointScreenProjector {
    let globeHorizonFadeBandWidth: Float = 0.03

    func project(snapshot: TilePointToScreenPointSnapshot,
                 frameContext: FrameContext,
                 tileOriginData: [FlatTileOriginData]) -> [ScreenPointOutput] {
        guard snapshot.pointsCount > 0 else {
            return []
        }

        switch frameContext.screenSpaceProjectionMode {
        case .flat:
            return projectFlat(snapshot: snapshot,
                               frameContext: frameContext,
                               tileOriginData: tileOriginData)
        case .globe:
            return projectGlobe(snapshot: snapshot,
                                frameContext: frameContext)
        }
    }

    private func projectFlat(snapshot: TilePointToScreenPointSnapshot,
                             frameContext: FrameContext,
                             tileOriginData: [FlatTileOriginData]) -> [ScreenPointOutput] {
        let viewport = SIMD2<Float>(Float(frameContext.drawSize.width), Float(frameContext.drawSize.height))
        let cameraMatrix = frameContext.cameraMatrices.projectionView
        var outputs = Array(repeating: ScreenPointOutput(position: .zero, depth: 0, visible: 0),
                            count: snapshot.pointsCount)

        for index in snapshot.pointInputs.indices {
            let input = snapshot.pointInputs[index]
            let tileSlotIndex = Int(input.tileSlotIndex)
            guard tileSlotIndex >= 0,
                  tileSlotIndex < snapshot.tileSlotVisibleTileIndices.count else {
                continue
            }

            let visibleTileIndex = Int(snapshot.tileSlotVisibleTileIndices[tileSlotIndex])
            guard visibleTileIndex >= 0,
                  visibleTileIndex < tileOriginData.count else {
                continue
            }

            let originData = tileOriginData[visibleTileIndex]
            let local = SIMD2<Float>(input.uv.x * originData.size,
                                     (1.0 - input.uv.y) * originData.size)
            let worldPosition = originData.panRelativeOrigin + local
            let world = SIMD4<Float>(worldPosition.x, worldPosition.y, 0.0, 1.0)
            let clip = cameraMatrix * world
            outputs[index] = screenPointFromClip(clip: clip, viewportSize: viewport)
        }

        return outputs
    }

    private func projectGlobe(snapshot: TilePointToScreenPointSnapshot,
                              frameContext: FrameContext) -> [ScreenPointOutput] {
        let viewport = SIMD2<Float>(Float(frameContext.drawSize.width), Float(frameContext.drawSize.height))
        let cameraUniform = frameContext.cameraUniform
        let globe = frameContext.globeRenderUniform
        let constants = GlobeProjectionConstants(globe: globe)
        var outputs = Array(repeating: ScreenPointOutput(position: .zero, depth: 0, visible: 0),
                            count: snapshot.pointsCount)

        for index in snapshot.pointInputs.indices {
            let input = snapshot.pointInputs[index]
            let projection = globeProjectTileUV(input: input,
                                                cameraUniform: cameraUniform,
                                                constants: constants)
            var output = screenPointFromClip(clip: projection.clip, viewportSize: viewport)
            if output.visible != 0 {
                let visibility = globeProjectionVisibility(worldPosition: projection.worldPosition,
                                                           cameraUniform: cameraUniform,
                                                           constants: constants)
                output.visible = visibility.visible ? output.visible : 0
                output.visibilityAlpha = visibility.alpha
            }
            outputs[index] = output
        }

        return outputs
    }

    private func screenPointFromClip(clip: SIMD4<Float>,
                                     viewportSize: SIMD2<Float>) -> ScreenPointOutput {
        guard clip.w > 0.0 else {
            return ScreenPointOutput(position: .zero, depth: 0.0, visible: 0, visibilityAlpha: 0.0)
        }

        let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
        let depth = clip.z / clip.w
        let position = (ndc * 0.5 + 0.5) * viewportSize
        return ScreenPointOutput(position: position, depth: depth, visible: 1, visibilityAlpha: 1.0)
    }

    private func globeProjectTileUV(input: TilePointInput,
                                    cameraUniform: CameraUniform,
                                    constants: GlobeProjectionConstants) -> GlobeProjectionResult {
        let zPow = powf(2.0, Float(input.tile.z))
        let size = 1.0 / zPow
        let vertexUvX = input.uv.x / zPow + size * Float(input.tile.x)
        let mercatorV = (Float(input.tile.y) + input.uv.y) / zPow
        let latitudeAtUv = atan(sinh(Float.pi * (1.0 - 2.0 * mercatorV)))
        let longitudeAtUv = vertexUvX * (2.0 * Float.pi) - Float.pi
        return globeProjectLatLon(latitude: latitudeAtUv,
                                  longitude: longitudeAtUv,
                                  cameraUniform: cameraUniform,
                                  constants: constants)
    }

    private func globeProjectLatLon(latitude: Float,
                                    longitude: Float,
                                    cameraUniform: CameraUniform,
                                    constants: GlobeProjectionConstants) -> GlobeProjectionResult {
        let sphereWorldPosition = constants.rotatedSphereWorldPosition(latitude: latitude,
                                                                       longitude: longitude)
        let flatWorldPosition = constants.flatWorldPosition(latitude: latitude,
                                                            longitude: longitude)
        let transition = constants.globe.transition
        let worldPosition = sphereWorldPosition + (flatWorldPosition - sphereWorldPosition) * transition
        let clip = cameraUniform.matrix * SIMD4<Float>(worldPosition, 1.0)
        return GlobeProjectionResult(clip: clip, worldPosition: worldPosition)
    }

    func globeProjectionVisibility(worldPosition: SIMD3<Float>,
                                   cameraUniform: CameraUniform,
                                   globe: Globe) -> (visible: Bool, alpha: Float) {
        globeProjectionVisibility(worldPosition: worldPosition,
                                  cameraUniform: cameraUniform,
                                  constants: GlobeProjectionConstants(globe: globe))
    }

    private func globeProjectionVisibility(worldPosition: SIMD3<Float>,
                                           cameraUniform: CameraUniform,
                                           constants: GlobeProjectionConstants) -> (visible: Bool, alpha: Float) {
        let globeCenter = SIMD3<Float>(0.0, 0.0, -constants.globe.radius)
        let toCamera = cameraUniform.eye - globeCenter
        if simd_length(toCamera) <= 0.0 || constants.globe.transition >= 0.95 {
            return (true, 1.0)
        }

        let toCameraLength = simd_length(toCamera)
        let radius = max(constants.globe.radius, 1e-6)
        let dotToCamera = simd_dot(worldPosition - globeCenter, toCamera)
        let normalization = max(toCameraLength * radius, 1e-6)
        let normalizedDot = dotToCamera / normalization
        let normalizedThreshold = constants.horizonThreshold / normalization
        let visibilityDelta = normalizedDot - normalizedThreshold

        if visibilityDelta <= -globeHorizonFadeBandWidth {
            return (false, 0.0)
        }

        let alpha = smoothstep(edge0: -globeHorizonFadeBandWidth,
                               edge1: globeHorizonFadeBandWidth,
                               x: visibilityDelta)
        return (true, alpha)
    }

    private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = simd_clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }
}

private struct GlobeProjectionResult {
    let clip: SIMD4<Float>
    let worldPosition: SIMD3<Float>
}

private struct GlobeProjectionConstants {
    let globe: Globe
    let panLatitude: Float
    let panLongitude: Float
    let mapSize: Float
    let panMercatorY: Float
    let rotationMatrix: matrix_float4x4
    let horizonThreshold: Float

    init(globe: Globe) {
        self.globe = globe
        let maxLatitude = Float(ImmersiveMapProjection.maxMercatorLatitude)
        self.panLatitude = globe.panY * maxLatitude
        self.panLongitude = globe.panX * .pi
        let distortion = cos(panLatitude)
        let mapSizeScale = (1.0 - globe.transition) * distortion + globe.transition
        self.mapSize = 2.0 * .pi * globe.radius * mapSizeScale
        self.panMercatorY = Float(ImmersiveMapProjection.yMercatorNormalized(latitude: Double(panLatitude)))
        self.rotationMatrix = GlobeProjectionConstants.makeRotationMatrix(panLatitude: panLatitude,
                                                                          panLongitude: panLongitude)
        let horizonFade = GlobeProjectionConstants.smoothstep(edge0: 0.8, edge1: 0.95, x: globe.transition)
        self.horizonThreshold = (1.0 - horizonFade) * (globe.radius * globe.radius) + horizonFade * -1e6
    }

    func rotatedSphereWorldPosition(latitude: Float,
                                    longitude: Float) -> SIMD3<Float> {
        let phi = latitude - (.pi * 0.5)
        let theta = longitude + .pi

        let x = globe.radius * sin(phi) * sin(theta)
        let y = globe.radius * cos(phi)
        let z = globe.radius * sin(phi) * cos(theta)
        let rotatedPosition = simd_transpose(rotationMatrix) * SIMD4<Float>(x, y, z, 1.0)
        return SIMD3<Float>(rotatedPosition.x,
                            rotatedPosition.y,
                            rotatedPosition.z - globe.radius)
    }

    func flatWorldPosition(latitude: Float,
                           longitude: Float) -> SIMD3<Float> {
        let normalizedWorldX = (longitude + .pi) / (2.0 * .pi)
        let mercatorY = Float(ImmersiveMapProjection.yMercatorNormalized(latitude: Double(latitude)))
        let halfMapSize = mapSize * 0.5
        let flatX = Float(ImmersiveMapProjection.wrap(value: Double(normalizedWorldX * mapSize - halfMapSize + globe.panX * halfMapSize),
                                             size: Double(mapSize)))
        let flatY = (mercatorY - panMercatorY) * halfMapSize
        return SIMD3<Float>(flatX, flatY, 0.0)
    }

    private static func makeRotationMatrix(panLatitude: Float,
                                           panLongitude: Float) -> matrix_float4x4 {
        let cx = cos(-panLatitude)
        let sx = sin(-panLatitude)
        let cy = cos(-panLongitude)
        let sy = sin(-panLongitude)

        return matrix_float4x4(columns: (
            SIMD4<Float>(cy, 0, -sy, 0),
            SIMD4<Float>(sy * sx, cx, cy * sx, 0),
            SIMD4<Float>(sy * cx, -sx, cy * cx, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    private static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = simd_clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }
}
