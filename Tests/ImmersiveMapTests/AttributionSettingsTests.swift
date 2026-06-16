// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class AttributionSettingsTests: XCTestCase {
    func testDefaultAttributionLinksToArtemBobkinXAccount() {
        let attribution = ImmersiveMapSettings.default.attribution

        XCTAssertEqual(attribution.linkURL, URL(string: "https://x.com/BobkinArtem"))
    }
}
