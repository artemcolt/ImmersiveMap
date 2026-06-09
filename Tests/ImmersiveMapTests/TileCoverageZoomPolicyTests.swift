// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class TileCoverageZoomPolicyTests: XCTestCase {
    func testFlatModeKeepsSingleCoverageZoomAtFlooredCameraZoom() {
        let plan = TileCoverageZoomPolicy.resolve(cameraZoom: 1.74,
                                                  renderSurfaceMode: .flat,
                                                  maximumZoomLevel: 20)

        XCTAssertEqual(plan.baseZoom, 1)
        XCTAssertNil(plan.detailZoom)
    }

    func testGlobeModeUsesCoarseBaseAndAheadDetailZoom() {
        let plan = TileCoverageZoomPolicy.resolve(cameraZoom: 1.74,
                                                  renderSurfaceMode: .spherical,
                                                  maximumZoomLevel: 20)

        XCTAssertEqual(plan.baseZoom, 1)
        XCTAssertEqual(plan.detailZoom, 3)
    }

    func testGlobeDetailZoomClampsToMaximumZoom() {
        let plan = TileCoverageZoomPolicy.resolve(cameraZoom: 19.7,
                                                  renderSurfaceMode: .spherical,
                                                  maximumZoomLevel: 20)

        XCTAssertEqual(plan.baseZoom, 19)
        XCTAssertEqual(plan.detailZoom, 20)
    }

    func testGlobeDoesNotCreateDuplicateDetailZoomWhenBaseAlreadyAtMaximum() {
        let plan = TileCoverageZoomPolicy.resolve(cameraZoom: 20.0,
                                                  renderSurfaceMode: .spherical,
                                                  maximumZoomLevel: 20)

        XCTAssertEqual(plan.baseZoom, 20)
        XCTAssertNil(plan.detailZoom)
    }
}
