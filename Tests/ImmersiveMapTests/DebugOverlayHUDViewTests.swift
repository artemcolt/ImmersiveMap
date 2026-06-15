// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

@testable import ImmersiveMap
import UIKit
import XCTest

@MainActor
final class DebugOverlayHUDViewTests: XCTestCase {
    func testSurfaceModeControlInvokesCallback() {
        let view = DebugOverlayHUDView()
        var didRequestSurfaceSwitch = false
        view.onSurfaceModeSwitchRequested = {
            didRequestSurfaceSwitch = true
        }

        view.simulateSurfaceModeSwitchForTesting()

        XCTAssertTrue(didRequestSurfaceSwitch)
    }
}

#endif
