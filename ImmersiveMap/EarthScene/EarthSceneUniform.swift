// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import simd

struct EarthSceneUniform {
    var sunDirection: SIMD3<Float>
    var isEnabled: UInt32
    var daySideMinimumBrightness: Float
    var nightSideBrightness: Float
    var terminatorFadeWidth: Float
    var nightLightsIntensity: Float
    var nightLightsTerminatorFadeWidth: Float
    var nightLightsEnabled: UInt32
    var _padding0: UInt32

    static let minimumFadeWidth: Float = 0.001

    static let disabled = EarthSceneUniform(
        sunDirection: SIMD3<Float>(0, 0, 1),
        isEnabled: 0,
        daySideMinimumBrightness: 0,
        nightSideBrightness: 0,
        terminatorFadeWidth: minimumFadeWidth,
        nightLightsIntensity: 0,
        nightLightsTerminatorFadeWidth: minimumFadeWidth,
        nightLightsEnabled: 0,
        _padding0: 0
    )

    init(settings: ImmersiveMapSettings.EarthSceneSettings, now: Date = Date()) {
        guard settings.isEnabled else {
            self = Self.disabled
            return
        }

        let date = settings.timeMode.resolvedDate(now: now)
        let nightLights = settings.nightLights

        self.init(
            sunDirection: EarthSceneSunCalculator.earthFixedSunDirection(at: date),
            isEnabled: 1,
            daySideMinimumBrightness: Self.clampedUnit(settings.daySideMinimumBrightness),
            nightSideBrightness: Self.clampedUnit(settings.nightSideBrightness),
            terminatorFadeWidth: Self.resolvedFadeWidth(settings.terminatorFadeWidth),
            nightLightsIntensity: Self.clampedUnit(nightLights.intensity),
            nightLightsTerminatorFadeWidth: Self.resolvedFadeWidth(nightLights.terminatorFadeWidth),
            nightLightsEnabled: nightLights.isEnabled ? 1 : 0,
            _padding0: 0
        )
    }

    private init(sunDirection: SIMD3<Float>,
                 isEnabled: UInt32,
                 daySideMinimumBrightness: Float,
                 nightSideBrightness: Float,
                 terminatorFadeWidth: Float,
                 nightLightsIntensity: Float,
                 nightLightsTerminatorFadeWidth: Float,
                 nightLightsEnabled: UInt32,
                 _padding0: UInt32) {
        self.sunDirection = sunDirection
        self.isEnabled = isEnabled
        self.daySideMinimumBrightness = daySideMinimumBrightness
        self.nightSideBrightness = nightSideBrightness
        self.terminatorFadeWidth = terminatorFadeWidth
        self.nightLightsIntensity = nightLightsIntensity
        self.nightLightsTerminatorFadeWidth = nightLightsTerminatorFadeWidth
        self.nightLightsEnabled = nightLightsEnabled
        self._padding0 = _padding0
    }

    private static func clampedUnit(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }

    private static func resolvedFadeWidth(_ value: Float) -> Float {
        guard value.isFinite else {
            return minimumFadeWidth
        }

        return max(value, minimumFadeWidth)
    }
}
