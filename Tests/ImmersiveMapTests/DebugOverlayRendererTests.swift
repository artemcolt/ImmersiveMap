// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class DebugOverlayRendererTests: XCTestCase {
    func testHudOverlayDoesNotRequireMetalDebugPass() {
        var settings = ImmersiveMapSettings.default.debug
        settings.overlayEnabled = true
        settings.tileOverlayEnabled = false

        XCTAssertFalse(RenderDebugOverlayPolicy.shouldEncode(settings))
    }

    func testTileOverlayRequiresMetalDebugPass() {
        var settings = ImmersiveMapSettings.default.debug
        settings.overlayEnabled = false
        settings.tileOverlayEnabled = true

        XCTAssertTrue(RenderDebugOverlayPolicy.shouldEncode(settings))
    }

    func testHudSnapshotIsNilWhenOverlayIsDisabled() {
        var settings = ImmersiveMapSettings.default.debug
        settings.overlayEnabled = false

        let snapshot = DebugOverlayHUDSnapshot.make(
            settings: settings,
            zoom: 4,
            latitude: 55,
            longitude: 37,
            cameraDebugLines: [],
            diagnostics: nil
        )

        XCTAssertNil(snapshot)
    }

    func testHudSnapshotIncludesCoordinatesAndDiagnosticsLines() {
        var settings = ImmersiveMapSettings.default.debug
        settings.overlayEnabled = true
        let diagnostics = FrameDiagnostics(frameIndex: 42, frameTime: 16.7)

        let snapshot = DebugOverlayHUDSnapshot.make(
            settings: settings,
            zoom: 5.412,
            latitude: 55.7558,
            longitude: 37.6173,
            cameraDebugLines: ["camera z:5.41 pitch:36.00 bearing:18.00"],
            diagnostics: diagnostics
        )

        XCTAssertEqual(snapshot?.coordinateLines.zoom, "z: 5.41")
        XCTAssertEqual(snapshot?.coordinateLines.latLon, "lat: 55.756 lon: 37.617")
        XCTAssertEqual(snapshot?.diagnosticsLines.first, "camera z:5.41 pitch:36.00 bearing:18.00")
        XCTAssertTrue(snapshot?.diagnosticsLines.contains { $0.hasPrefix("frame: 42") } == true)
    }

    func testOverlayDiagnosticsIncludeCameraLinesWithoutFrameDiagnostics() {
        let lines = DebugOverlayRenderer.makeOverlayDiagnosticsTextLines(
            cameraDebugLines: ["camera z:5.41 pitch:36.00 bearing:18.00"],
            diagnostics: nil
        )

        XCTAssertEqual(lines, ["camera z:5.41 pitch:36.00 bearing:18.00"])
    }

    func testOverlayDiagnosticsPrependCameraLinesBeforeFrameDiagnostics() {
        let diagnostics = FrameDiagnostics(frameIndex: 42, frameTime: 16.7)

        let lines = DebugOverlayRenderer.makeOverlayDiagnosticsTextLines(
            cameraDebugLines: ["camera z:5.41 pitch:36.00 bearing:18.00"],
            diagnostics: diagnostics
        )

        XCTAssertEqual(lines.first, "camera z:5.41 pitch:36.00 bearing:18.00")
        XCTAssertTrue(lines.contains { $0.hasPrefix("frame: 42") })
    }
}
