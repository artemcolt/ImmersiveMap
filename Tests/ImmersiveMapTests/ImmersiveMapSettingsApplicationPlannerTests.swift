// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class ImmersiveMapSettingsApplicationPlannerTests: XCTestCase {
    func testEarthSceneTimeModeChangeIsLiveApplied() {
        let oldSettings = ImmersiveMapSettings.default
        var newSettings = oldSettings
        newSettings.scene.earth.timeMode = .fixed(Date(timeIntervalSince1970: 1_767_225_600))

        let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: oldSettings, to: newSettings)

        XCTAssertEqual(plan.changedDomains, [.scene])
        XCTAssertEqual(plan.actions, [.liveApply])
        XCTAssertFalse(plan.requiresRendererRecreation)
    }

    func testEarthSceneBrightnessChangeIsLiveApplied() {
        let oldSettings = ImmersiveMapSettings.default
        var newSettings = oldSettings
        newSettings.scene.earth.daySideMinimumBrightness = 0.76

        let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: oldSettings, to: newSettings)

        XCTAssertEqual(plan.changedDomains, [.scene])
        XCTAssertEqual(plan.actions, [.liveApply])
        XCTAssertFalse(plan.requiresRendererRecreation)
    }

    func testEarthSceneNightLightsIntensityChangeIsLiveApplied() {
        let oldSettings = ImmersiveMapSettings.default
        var newSettings = oldSettings
        newSettings.scene.earth.nightLights.intensity = 0.55

        let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: oldSettings, to: newSettings)

        XCTAssertEqual(plan.changedDomains, [.scene])
        XCTAssertEqual(plan.actions, [.liveApply])
        XCTAssertFalse(plan.requiresRendererRecreation)
    }

    func testEarthSceneSunSettingsChangeIsLiveApplied() {
        let oldSettings = ImmersiveMapSettings.default
        var newSettings = oldSettings
        newSettings.scene.earth.sun.glowIntensity = 0.25

        let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: oldSettings, to: newSettings)

        XCTAssertEqual(plan.changedDomains, [.scene])
        XCTAssertEqual(plan.actions, [.liveApply])
        XCTAssertFalse(plan.requiresRendererRecreation)
    }
}
