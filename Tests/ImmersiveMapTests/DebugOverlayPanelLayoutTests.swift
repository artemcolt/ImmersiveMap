// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class DebugOverlayPanelLayoutTests: XCTestCase {
    func testBodyHeightIsCappedToAvailablePanelSpace() {
        let height = DebugOverlayPanelLayout.visibleBodyHeight(preferredBodyHeight: 1400,
                                                              viewportHeight: 844,
                                                              panelMinY: 20,
                                                              chromeHeight: 220,
                                                              minimumBodyHeight: 48)

        XCTAssertEqual(height, 604)
    }

    func testBodyHeightKeepsPreferredHeightWhenItFits() {
        let height = DebugOverlayPanelLayout.visibleBodyHeight(preferredBodyHeight: 320,
                                                              viewportHeight: 844,
                                                              panelMinY: 20,
                                                              chromeHeight: 220,
                                                              minimumBodyHeight: 48)

        XCTAssertEqual(height, 320)
    }
}
