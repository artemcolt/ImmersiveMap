// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import simd

struct EarthSceneSunVisualState {
    var screenCenter: SIMD2<Float>
    var clampedScreenCenter: SIMD2<Float>
    var globeScreenCenter: SIMD2<Float>
    var globeScreenRadius: Float
    var diskAlpha: Float
    var edgeGlareAlpha: Float
    var limbHaloAlpha: Float
    var isEnabled: UInt32
    var padding: UInt32 = 0

    var hasVisibleContribution: Bool {
        isEnabled != 0 && (diskAlpha > 0 || edgeGlareAlpha > 0 || limbHaloAlpha > 0)
    }

    static let disabled = EarthSceneSunVisualState(
        screenCenter: SIMD2<Float>(repeating: 0.5),
        clampedScreenCenter: SIMD2<Float>(repeating: 0.5),
        globeScreenCenter: SIMD2<Float>(repeating: 0.5),
        globeScreenRadius: 0,
        diskAlpha: 0,
        edgeGlareAlpha: 0,
        limbHaloAlpha: 0,
        isEnabled: 0
    )

    static func make(earthScene: EarthSceneUniform,
                     globe: GlobeUniform,
                     cameraMatrix: matrix_float4x4,
                     drawSize: CGSize) -> EarthSceneSunVisualState {
        guard earthScene.isEnabled != 0,
              earthScene.sunVisualEnabled != 0 else {
            return .disabled
        }

        let width = Float(drawSize.width)
        let height = Float(drawSize.height)
        guard width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return .disabled
        }

        let rawDirection = earthScene.sunDirection
        let directionLength = simd_length(rawDirection)
        guard directionLength.isFinite,
              directionLength > 0 else {
            return .disabled
        }

        let direction = rawDirection / directionLength
        guard direction.z >= -0.0001 else {
            return .disabled
        }

        // MVP uses deterministic normalized-screen projection, which naturally stays inside 0...1.
        // Keep the unused inputs and clamped output for the later exact projection/offscreen glare path.
        _ = globe
        _ = cameraMatrix

        let screenCenter = SIMD2<Float>(
            0.5 + direction.x * 0.5,
            0.5 - direction.y * 0.5
        )
        let clampedScreenCenter = SIMD2<Float>(
            Self.clampedUnit(screenCenter.x),
            Self.clampedUnit(screenCenter.y)
        )
        let globeScreenCenter = SIMD2<Float>(repeating: 0.5)
        let globeScreenRadius: Float = 0.25
        let aspectScale = SIMD2<Float>(width / height, 1)
        let distanceToGlobeCenter = simd_length((screenCenter - globeScreenCenter) * aspectScale)

        let diskAlpha: Float
        let edgeGlareAlpha: Float
        let limbHaloAlpha: Float
        if distanceToGlobeCenter <= globeScreenRadius {
            diskAlpha = 0
            edgeGlareAlpha = 0

            let limbDistance = abs(globeScreenRadius - distanceToGlobeCenter)
            let haloWidth = max(earthScene.sunLimbHaloWidth, EarthSceneUniform.minimumFadeWidth)
            let haloFade = Self.clampedUnit(1 - limbDistance / haloWidth)
            limbHaloAlpha = earthScene.sunLimbHaloIntensity * haloFade
        } else {
            diskAlpha = earthScene.sunDiskIntensity
            edgeGlareAlpha = earthScene.sunEdgeGlareIntensity
            limbHaloAlpha = 0
        }

        return EarthSceneSunVisualState(
            screenCenter: screenCenter,
            clampedScreenCenter: clampedScreenCenter,
            globeScreenCenter: globeScreenCenter,
            globeScreenRadius: globeScreenRadius,
            diskAlpha: diskAlpha,
            edgeGlareAlpha: edgeGlareAlpha,
            limbHaloAlpha: limbHaloAlpha,
            isEnabled: 1
        )
    }

    private static func clampedUnit(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
