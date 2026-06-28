// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class VisibilityCycleTests: XCTestCase {
    func testProcessNextGroupsPublishesPartialBaseCollisionVisibility() {
        var cycle = VisibilityCycle(topologyGeneration: 0,
                                    cameraFingerprint: 10,
                                    horizonReservationSignature: [],
                                    viewportSize: SIMD2<Float>(200, 200),
                                    baseCount: 3,
                                    roadCount: 0,
                                    groups: [
                                        makeBaseGroup(index: 0,
                                                      position: SIMD2<Float>(50, 50),
                                                      priority: 0),
                                        makeBaseGroup(index: 1,
                                                      position: SIMD2<Float>(54, 50),
                                                      priority: 1),
                                        makeBaseGroup(index: 2,
                                                      position: SIMD2<Float>(120, 50),
                                                      priority: 2)
                                    ],
                                    cellSizePx: 32)

        cycle.processNextGroups(maxGroupCount: 1)

        XCTAssertEqual(cycle.baseCollisionVisibility, [.visible, .unknown, .unknown])
        XCTAssertFalse(cycle.isComplete)

        cycle.processNextGroups(maxGroupCount: 1)

        XCTAssertEqual(cycle.baseCollisionVisibility, [.visible, .hidden, .unknown])
        XCTAssertFalse(cycle.isComplete)
    }

    func testProcessNextGroupsTracksPartialRoadVisibilityResolution() {
        var cycle = VisibilityCycle(topologyGeneration: 0,
                                    cameraFingerprint: 10,
                                    horizonReservationSignature: [],
                                    viewportSize: SIMD2<Float>(200, 200),
                                    baseCount: 0,
                                    roadCount: 2,
                                    groups: [
                                        makeRoadGroup(index: 0,
                                                      position: SIMD2<Float>(50, 50),
                                                      priority: 0),
                                        makeRoadGroup(index: 1,
                                                      position: SIMD2<Float>(120, 50),
                                                      priority: 1)
                                    ],
                                    cellSizePx: 32)

        cycle.processNextGroups(maxGroupCount: 1)

        XCTAssertEqual(cycle.roadInstanceVisibility, [true, false])
        XCTAssertEqual(cycle.roadInstanceVisibilityResolved, [true, false])
        XCTAssertFalse(cycle.isComplete)
    }

    func testMergingPartialBaseCollisionVisibilityKeepsPreviousForUnknown() {
        let result = BaseLabelPrepareSubsystem.mergedBaseCollisionVisibility(
            current: [.visible, .hidden, .visible],
            cycleVisibility: [.unknown, .unknown, .hidden]
        )

        XCTAssertEqual(result, [.visible, .hidden, .hidden])
    }

    func testMergingPartialBaseCollisionVisibilityHidesNewUnknownLabels() {
        let result = BaseLabelPrepareSubsystem.mergedBaseCollisionVisibility(
            current: [.visible],
            cycleVisibility: [.unknown, .visible, .unknown]
        )

        XCTAssertEqual(result, [.visible, .visible, .hidden])
    }

    func testActiveCycleIsNotReplacedWhenOnlyCameraFingerprintChanges() {
        let cycle = VisibilityCycle(topologyGeneration: 4,
                                    cameraFingerprint: 10,
                                    horizonReservationSignature: [],
                                    viewportSize: SIMD2<Float>(200, 200),
                                    baseCount: 1,
                                    roadCount: 0,
                                    groups: [
                                        makeBaseGroup(index: 0,
                                                      position: SIMD2<Float>(50, 50),
                                                      priority: 0)
                                    ],
                                    cellSizePx: 32)

        let shouldReplace = BaseLabelPrepareSubsystem.shouldReplaceActiveVisibilityCycle(
            cycle,
            latestCameraFingerprint: 11,
            forceRestart: false
        )

        XCTAssertFalse(shouldReplace)
    }

    func testStaleCameraCycleCanPublishWhenTopologyIsCurrent() {
        let cycle = VisibilityCycle(topologyGeneration: 4,
                                    cameraFingerprint: 10,
                                    horizonReservationSignature: [],
                                    viewportSize: SIMD2<Float>(200, 200),
                                    baseCount: 1,
                                    roadCount: 0,
                                    groups: [
                                        makeBaseGroup(index: 0,
                                                      position: SIMD2<Float>(50, 50),
                                                      priority: 0)
                                    ],
                                    cellSizePx: 32)

        let shouldPublish = BaseLabelPrepareSubsystem.shouldPublishVisibilityCycle(
            cycle,
            topologyGeneration: 4
        )

        XCTAssertTrue(shouldPublish)
    }

    private func makeBaseGroup(index: Int,
                               position: SIMD2<Float>,
                               priority: Int) -> VisibilityCollisionGroup {
        let candidate = ScreenCollisionCandidate(position: position,
                                                 halfSize: SIMD2<Float>(10, 10),
                                                 priority: priority,
                                                 secondaryPriority: 0,
                                                 groupId: 0,
                                                 isEnabled: true)
        return VisibilityCollisionGroup(target: .base(index),
                                        members: [candidate],
                                        priority: priority,
                                        secondaryPriority: 0)
    }

    private func makeRoadGroup(index: Int,
                               position: SIMD2<Float>,
                               priority: Int) -> VisibilityCollisionGroup {
        let candidate = ScreenCollisionCandidate(position: position,
                                                 halfSize: SIMD2<Float>(10, 10),
                                                 priority: priority,
                                                 secondaryPriority: 0,
                                                 groupId: UInt64(index + 1),
                                                 isEnabled: true)
        return VisibilityCollisionGroup(target: .road(index),
                                        members: [candidate],
                                        priority: priority,
                                        secondaryPriority: 0)
    }
}
