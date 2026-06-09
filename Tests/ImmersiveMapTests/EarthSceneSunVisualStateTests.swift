// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import simd
import XCTest

final class EarthSceneSunVisualStateTests: XCTestCase {
    func testDisabledEarthSceneReturnsDisabledState() {
        let state = EarthSceneSunVisualState.make(
            earthScene: .disabled,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1024, height: 768)
        )

        XCTAssertEqual(state.screenCenter.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.screenCenter.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.clampedScreenCenter.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.clampedScreenCenter.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.globeScreenCenter.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.globeScreenCenter.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.globeScreenRadius, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.diskAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.isEnabled, 0)
        XCTAssertEqual(state.padding, 0)
    }

    func testVisibleSunOutsideGlobeSilhouetteDrawsDiskAndGlare() {
        var earthScene = Self.earthScene()
        earthScene.sunDirection = normalize(SIMD3<Float>(0.9, 0, 0.44))

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1024, height: 768)
        )

        XCTAssertEqual(state.isEnabled, 1)
        XCTAssertGreaterThan(state.diskAlpha, 0)
        XCTAssertGreaterThan(state.edgeGlareAlpha, 0)
        XCTAssertEqual(state.limbHaloAlpha, 0.0, accuracy: 0.0001)
    }

    func testSunInsideGlobeSilhouetteNearLimbSuppressesDiskAndKeepsHalo() {
        var earthScene = Self.earthScene()
        earthScene.sunDirection = normalize(SIMD3<Float>(0.48, 0, 0.88))

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1024, height: 1024)
        )

        XCTAssertEqual(state.isEnabled, 1)
        XCTAssertEqual(state.diskAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0.0, accuracy: 0.0001)
        XCTAssertGreaterThan(state.limbHaloAlpha, 0)
    }

    func testSunBehindCameraSuppressesAllVisibleContributions() {
        var earthScene = Self.earthScene()
        earthScene.sunDirection = normalize(SIMD3<Float>(0.2, 0, -1))

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1024, height: 768)
        )

        XCTAssertEqual(state.isEnabled, 0)
        XCTAssertEqual(state.diskAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, 0.0, accuracy: 0.0001)
    }
}

private extension EarthSceneSunVisualStateTests {
    static let globe = GlobeUniform(panX: 0, panY: 0, radius: 1, transition: 1)

    static func earthScene() -> EarthSceneUniform {
        EarthSceneUniform(
            settings: ImmersiveMapSettings.EarthSceneSettings(
                sun: .init(
                    diskIntensity: 0.8,
                    edgeGlareIntensity: 0.6,
                    limbHaloIntensity: 0.4,
                    limbHaloWidth: 0.1
                )
            ),
            now: .distantPast
        )
    }
}
