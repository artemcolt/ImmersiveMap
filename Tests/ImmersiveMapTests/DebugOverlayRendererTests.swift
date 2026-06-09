// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class DebugOverlayRendererTests: XCTestCase {
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
