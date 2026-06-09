// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import simd
import XCTest

final class EarthSceneSunVisualStateTests: XCTestCase {
    func testDisabledStateHasNoVisibleContribution() {
        XCTAssertFalse(EarthSceneSunVisualState.disabled.hasVisibleContribution)
    }

    func testOutsideGlobeStateHasVisibleContribution() {
        var earthScene = Self.earthScene()
        earthScene.sunDirection = normalize(SIMD3<Float>(0.9, 0, 0.44))

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1024, height: 768)
        )

        XCTAssertTrue(state.hasVisibleContribution)
    }

    func testInsideGlobeAwayFromLimbHasNoVisibleContribution() {
        var earthScene = Self.earthScene(limbHaloIntensity: 1)
        earthScene.sunDirection = SIMD3<Float>(0, 0, 1)

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1000, height: 1000)
        )

        XCTAssertEqual(state.isEnabled, 1)
        XCTAssertEqual(state.diskAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, 0.0, accuracy: 0.0001)
        XCTAssertFalse(state.hasVisibleContribution)
    }

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
        let expectedScreenCenter = SIMD2<Float>(
            0.5 + earthScene.sunDirection.x * 0.5,
            0.5 - earthScene.sunDirection.y * 0.5
        )

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1024, height: 768)
        )

        XCTAssertEqual(state.isEnabled, 1)
        XCTAssertEqual(state.screenCenter.x, expectedScreenCenter.x, accuracy: 0.0001)
        XCTAssertEqual(state.screenCenter.y, expectedScreenCenter.y, accuracy: 0.0001)
        XCTAssertEqual(state.clampedScreenCenter.x, expectedScreenCenter.x, accuracy: 0.0001)
        XCTAssertEqual(state.clampedScreenCenter.y, expectedScreenCenter.y, accuracy: 0.0001)
        XCTAssertEqual(state.globeScreenRadius, 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.diskAlpha, 1.0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, earthScene.sunEdgeGlareIntensity, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, 0.0, accuracy: 0.0001)
    }

    func testSunInsideGlobeSilhouetteNearLimbSuppressesDiskAndKeepsHalo() {
        var earthScene = Self.earthScene(limbHaloIntensity: 1)
        let direction = normalize(SIMD3<Float>(0.48, 0, 0.88))
        earthScene.sunDirection = direction
        let expectedGlobeRadius: Float = 0.25
        let expectedScreenCenter = SIMD2<Float>(
            0.5 + direction.x * 0.5,
            0.5
        )
        let distanceFromGlobeCenter = simd_length(expectedScreenCenter - SIMD2<Float>(0.5, 0.5))
        let limbDistance = abs(distanceFromGlobeCenter - expectedGlobeRadius)
        let expectedHalo = max(0, 1 - limbDistance / earthScene.sunLimbHaloWidth)

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1000, height: 1000)
        )

        XCTAssertEqual(state.isEnabled, 1)
        XCTAssertEqual(state.screenCenter.x, expectedScreenCenter.x, accuracy: 0.0001)
        XCTAssertEqual(state.screenCenter.y, expectedScreenCenter.y, accuracy: 0.0001)
        XCTAssertEqual(state.globeScreenRadius, expectedGlobeRadius, accuracy: 0.0001)
        XCTAssertEqual(state.diskAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, expectedHalo, accuracy: 0.0001)
    }

    func testWideViewportKeepsVerticalLimbRadiusStable() {
        var earthScene = Self.earthScene()
        earthScene.sunDirection = SIMD3<Float>(0, 0.5, Float(sqrt(0.75)))

        let state = EarthSceneSunVisualState.make(
            earthScene: earthScene,
            globe: Self.globe,
            cameraMatrix: matrix_identity_float4x4,
            drawSize: CGSize(width: 1000, height: 500)
        )

        XCTAssertEqual(state.globeScreenRadius, 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.diskAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0.0, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, earthScene.sunLimbHaloIntensity, accuracy: 0.0001)
    }

    func testValidFiniteDirectionsKeepClampedCenterEqualToProjectedCenter() {
        let directions = [
            normalize(SIMD3<Float>(0.9, 0, 0.44)),
            normalize(SIMD3<Float>(-0.7, 0.2, 0.8)),
            normalize(SIMD3<Float>(0, -0.9, 0.6))
        ]

        for direction in directions {
            var earthScene = Self.earthScene()
            earthScene.sunDirection = direction

            let state = EarthSceneSunVisualState.make(
                earthScene: earthScene,
                globe: Self.globe,
                cameraMatrix: matrix_identity_float4x4,
                drawSize: CGSize(width: 1024, height: 768)
            )

            XCTAssertEqual(state.clampedScreenCenter.x, state.screenCenter.x, accuracy: 0.0001)
            XCTAssertEqual(state.clampedScreenCenter.y, state.screenCenter.y, accuracy: 0.0001)
        }
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

    func testDisabledSunVisualReturnsDisabledState() {
        let earthScene = EarthSceneUniform(
            settings: ImmersiveMapSettings.EarthSceneSettings(sun: .init(isEnabled: false)),
            now: .distantPast
        )

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

    func testInvalidDrawSizeReturnsDisabledState() {
        let invalidSizes = [
            CGSize(width: 0, height: 768),
            CGSize(width: 1024, height: -1),
            CGSize(width: CGFloat.nan, height: 768),
            CGSize(width: 1024, height: CGFloat.infinity)
        ]

        for drawSize in invalidSizes {
            let state = EarthSceneSunVisualState.make(
                earthScene: Self.earthScene(),
                globe: Self.globe,
                cameraMatrix: matrix_identity_float4x4,
                drawSize: drawSize
            )

            XCTAssertEqual(state.isEnabled, 0)
            XCTAssertEqual(state.screenCenter.x, EarthSceneSunVisualState.disabled.screenCenter.x, accuracy: 0.0001)
            XCTAssertEqual(state.screenCenter.y, EarthSceneSunVisualState.disabled.screenCenter.y, accuracy: 0.0001)
            XCTAssertEqual(state.globeScreenRadius, EarthSceneSunVisualState.disabled.globeScreenRadius, accuracy: 0.0001)
            XCTAssertEqual(state.diskAlpha, 0.0, accuracy: 0.0001)
            XCTAssertEqual(state.edgeGlareAlpha, 0.0, accuracy: 0.0001)
            XCTAssertEqual(state.limbHaloAlpha, 0.0, accuracy: 0.0001)
        }
    }

    func testZeroOrNonFiniteSunDirectionReturnsDisabledState() {
        let invalidDirections = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(.nan, 0, 1),
            SIMD3<Float>(0, .infinity, 1)
        ]

        for direction in invalidDirections {
            var earthScene = Self.earthScene()
            earthScene.sunDirection = direction

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

    func testVisualStateMatchesShaderABIRelatedLayout() {
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.stride, 48)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.alignment, 8)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.screenCenter), 0)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.clampedScreenCenter), 8)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.globeScreenCenter), 16)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.globeScreenRadius), 24)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.diskAlpha), 28)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.edgeGlareAlpha), 32)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.limbHaloAlpha), 36)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.isEnabled), 40)
        XCTAssertEqual(MemoryLayout<EarthSceneSunVisualState>.offset(of: \.padding), 44)
    }
}

private extension EarthSceneSunVisualStateTests {
    static let globe = GlobeUniform(panX: 0, panY: 0, radius: 1, transition: 1)

    static func earthScene(limbHaloIntensity: Float = 0.4) -> EarthSceneUniform {
        EarthSceneUniform(
            settings: ImmersiveMapSettings.EarthSceneSettings(
                sun: .init(
                    edgeGlareIntensity: 0.6,
                    limbHaloIntensity: limbHaloIntensity,
                    limbHaloWidth: 0.1
                )
            ),
            now: .distantPast
        )
    }
}
