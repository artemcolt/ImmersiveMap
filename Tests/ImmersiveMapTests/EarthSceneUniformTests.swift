// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import simd
import XCTest

final class EarthSceneUniformTests: XCTestCase {
    func testDisabledUniformDisablesEarthSceneAndNightLights() {
        let uniform = EarthSceneUniform.disabled

        XCTAssertEqual(uniform.isEnabled, 0)
        XCTAssertEqual(uniform.nightLightsEnabled, 0)
    }

    func testEnabledFixedDateSettingsProduceExpectedSunDirection() throws {
        let date = try Date.utc(year: 2026, month: 6, day: 9, hour: 9, minute: 30, second: 0)
        let settings = ImmersiveMapSettings.EarthSceneSettings(
            timeMode: .fixed(date),
            nightLights: .init(isEnabled: true)
        )

        let uniform = EarthSceneUniform(settings: settings, now: .distantPast)
        let expectedDirection = EarthSceneSunCalculator.earthFixedSunDirection(at: date)

        XCTAssertEqual(uniform.isEnabled, 1)
        XCTAssertEqual(uniform.nightLightsEnabled, 1)
        XCTAssertEqual(uniform.sunDirection.x, expectedDirection.x, accuracy: 0.0001)
        XCTAssertEqual(uniform.sunDirection.y, expectedDirection.y, accuracy: 0.0001)
        XCTAssertEqual(uniform.sunDirection.z, expectedDirection.z, accuracy: 0.0001)
        XCTAssertEqual(simd_length(uniform.sunDirection), 1.0, accuracy: 0.0001)
    }

    func testShaderFacingFloatValuesAreClampedAndResolvedSafely() {
        let settings = ImmersiveMapSettings.EarthSceneSettings(
            daySideMinimumBrightness: -0.25,
            nightSideBrightness: 1.75,
            terminatorFadeWidth: -3.0,
            nightLights: .init(
                intensity: 2.5,
                terminatorFadeWidth: 0.0
            )
        )

        let uniform = EarthSceneUniform(settings: settings, now: .distantPast)

        XCTAssertEqual(uniform.daySideMinimumBrightness, 0.0, accuracy: 0.0001)
        XCTAssertEqual(uniform.nightSideBrightness, 1.0, accuracy: 0.0001)
        XCTAssertEqual(uniform.terminatorFadeWidth, EarthSceneUniform.minimumFadeWidth, accuracy: 0.0001)
        XCTAssertEqual(uniform.nightLightsIntensity, 1.0, accuracy: 0.0001)
        XCTAssertEqual(uniform.nightLightsTerminatorFadeWidth, EarthSceneUniform.minimumFadeWidth, accuracy: 0.0001)
    }

    func testRealtimeTimeModeUsesInjectedNowForSunDirection() throws {
        let now = try Date.utc(year: 2026, month: 12, day: 21, hour: 7, minute: 15, second: 0)
        let settings = ImmersiveMapSettings.EarthSceneSettings(timeMode: .realtime)

        let uniform = EarthSceneUniform(settings: settings, now: now)
        let expectedDirection = EarthSceneSunCalculator.earthFixedSunDirection(at: now)

        XCTAssertEqual(uniform.sunDirection.x, expectedDirection.x, accuracy: 0.0001)
        XCTAssertEqual(uniform.sunDirection.y, expectedDirection.y, accuracy: 0.0001)
        XCTAssertEqual(uniform.sunDirection.z, expectedDirection.z, accuracy: 0.0001)
    }

    func testUniformMatchesShaderABIRelatedLayout() {
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.stride, 48)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.alignment, 16)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunDirection), 0)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.isEnabled), 16)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.daySideMinimumBrightness), 20)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightSideBrightness), 24)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.terminatorFadeWidth), 28)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightLightsIntensity), 32)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightLightsTerminatorFadeWidth), 36)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightLightsEnabled), 40)
        XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \._padding0), 44)
    }
}

private extension Date {
    static func utc(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return try XCTUnwrap(components.date)
    }
}
