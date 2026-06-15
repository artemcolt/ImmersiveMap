// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import CoreGraphics
import MetalKit
import XCTest

final class GlobeAtlasPlacementPlannerTests: XCTestCase {
    func testSlotDepthCellSizesUseFixed4096Page() {
        XCTAssertEqual(GlobeAtlasSlotDepth.depth0.cellSize(pageSizePx: 4096), 4096)
        XCTAssertEqual(GlobeAtlasSlotDepth.depth1.cellSize(pageSizePx: 4096), 2048)
        XCTAssertEqual(GlobeAtlasSlotDepth.depth2.cellSize(pageSizePx: 4096), 1024)
        XCTAssertEqual(GlobeAtlasSlotDepth.depth3.cellSize(pageSizePx: 4096), 512)
        XCTAssertEqual(GlobeAtlasSlotDepth.depth4.cellSize(pageSizePx: 4096), 256)
    }

    func testDesiredDepthRoundsScreenDemandUpToNextAvailableCell() {
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 2300, pageSizePx: 4096), .depth0)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 1600, pageSizePx: 4096), .depth1)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 900, pageSizePx: 4096), .depth2)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 420, pageSizePx: 4096), .depth3)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 90, pageSizePx: 4096), .depth4)
    }

    func testDesiredDepthClampsOversizedDemandToFullPageCell() {
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 4097, pageSizePx: 4096), .depth0)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 8000, pageSizePx: 4096), .depth0)
    }

    func testDesiredDepthKeepsExactBoundaryInCurrentCell() {
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 4096, pageSizePx: 4096), .depth0)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 2048, pageSizePx: 4096), .depth1)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 1024, pageSizePx: 4096), .depth2)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 512, pageSizePx: 4096), .depth3)
        XCTAssertEqual(GlobeAtlasSlotDepth.desired(forScreenDemandPx: 256, pageSizePx: 4096), .depth4)
    }

    func testSingleCandidateUsesDesiredDepthEvenWithSmallFootprint() throws {
        let candidate = try makeCandidate(index: 0,
                                          source: Tile(x: 0, y: 0, z: 0),
                                          target: Tile(x: 0, y: 0, z: 0),
                                          screenDemandPx: 90,
                                          distanceToCamera: 0)

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [candidate])

        XCTAssertEqual(plan.allocations.map(\.atlasDepth), [.depth4])
    }

    func testFourCandidatesUseDesiredDepthEvenWithSmallFootprints() throws {
        let candidates = try (0..<4).map { index in
            try makeCandidate(index: index,
                              source: Tile(x: index % 2, y: index / 2, z: 1),
                              target: Tile(x: index % 2, y: index / 2, z: 1),
                              screenDemandPx: 90,
                              distanceToCamera: Float(index))
        }

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: candidates)

        XCTAssertEqual(plan.allocations.map(\.atlasDepth), Array(repeating: .depth4, count: 4))
    }

    func testCandidatesAllocateByDesiredDepthWithoutLayerPriority() throws {
        let small = try makeCandidate(index: 0,
                                      source: Tile(x: 0, y: 0, z: 1),
                                      target: Tile(x: 0, y: 0, z: 1),
                                      screenDemandPx: 90,
                                      distanceToCamera: 1)
        let large = try makeCandidate(index: 1,
                                      source: Tile(x: 0, y: 0, z: 3),
                                      target: Tile(x: 0, y: 0, z: 3),
                                      screenDemandPx: 900,
                                      distanceToCamera: 0)

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [small, large])

        XCTAssertEqual(plan.allocations.map(\.candidate.placementIndex), [1, 0])
        XCTAssertEqual(plan.allocations.map(\.atlasDepth), [.depth2, .depth4])
    }

    func testFallbackWithLargeFootprintGetsHighResolutionBeforeSmallExactTile() throws {
        let fallback = try makeCandidate(index: 0,
                                         source: Tile(x: 4, y: 2, z: 3),
                                         target: Tile(x: 17, y: 10, z: 5),
                                         screenDemandPx: 1700,
                                         distanceToCamera: 0.1)
        let exact = try makeCandidate(index: 1,
                                      source: Tile(x: 18, y: 10, z: 5),
                                      target: Tile(x: 18, y: 10, z: 5),
                                      screenDemandPx: 260,
                                      distanceToCamera: 0.2)

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [exact, fallback])

        assertNoOverlappingAllocations(plan.allocations)
        XCTAssertEqual(plan.allocations.count, 2)
        XCTAssertEqual(plan.allocations[0].candidate.placementIndex, 0)
        XCTAssertEqual(plan.allocations[0].atlasDepth, .depth1)
        XCTAssertEqual(plan.allocations[0].cellSizePx, 2048)
        XCTAssertEqual(plan.allocations[1].candidate.placementIndex, 1)
        XCTAssertEqual(plan.allocations[1].atlasDepth, .depth3)
        XCTAssertEqual(plan.allocations[1].cellSizePx, 512)
    }

    func testAllocatorCreatesSecondPageForMultipleFullPageDemands() throws {
        let first = try makeCandidate(index: 0,
                                      source: Tile(x: 0, y: 0, z: 2),
                                      target: Tile(x: 0, y: 0, z: 2),
                                      screenDemandPx: 3000,
                                      distanceToCamera: 0.0)
        let second = try makeCandidate(index: 1,
                                       source: Tile(x: 1, y: 0, z: 2),
                                       target: Tile(x: 1, y: 0, z: 2),
                                       screenDemandPx: 2800,
                                       distanceToCamera: 0.1)

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [first, second])

        assertNoOverlappingAllocations(plan.allocations)
        XCTAssertEqual(plan.allocations.map(\.pageIndex), [0, 1])
        XCTAssertEqual(plan.allocations.map(\.atlasDepth), [.depth0, .depth0])
        XCTAssertEqual(plan.pageSummaries.count, 2)
    }

    func testAllocatorCreatesPagesForAllFullPageDemands() throws {
        let candidates = try (0..<16).map { index in
            try makeCandidate(index: index,
                              source: Tile(x: index, y: 0, z: 4),
                              target: Tile(x: index, y: 0, z: 4),
                              screenDemandPx: 3000,
                              distanceToCamera: Float(index))
        }

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: candidates)

        assertNoOverlappingAllocations(plan.allocations)
        XCTAssertEqual(plan.allocations.count, 16)
        XCTAssertEqual(plan.pageSummaries.count, 16)
        XCTAssertEqual(plan.skippedAllocationCount, 0)
        XCTAssertEqual(plan.downgradedAllocationCount, 0)
        XCTAssertEqual(Set(plan.allocations.map(\.atlasDepth)), [.depth0])
    }

    func testAllocatorKeepsFullPageSlotsWhenCoverageAllowsIt() throws {
        let candidates = try (0..<3).map { index in
            try makeCandidate(index: index,
                              source: Tile(x: index, y: 0, z: 2),
                              target: Tile(x: index, y: 0, z: 2),
                              screenDemandPx: 3000,
                              distanceToCamera: Float(index))
        }

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: candidates)

        assertNoOverlappingAllocations(plan.allocations)
        XCTAssertEqual(plan.allocations.count, 3)
        XCTAssertEqual(plan.skippedAllocationCount, 0)
        XCTAssertEqual(plan.allocations.map(\.atlasDepth), [.depth0, .depth0, .depth0])
    }

    func testAllocatorCreatesSecondPageForDepthOneDemandsInsteadOfDowngrading() throws {
        let candidates = try (0..<5).map { index in
            try makeCandidate(index: index,
                              source: Tile(x: index, y: 0, z: 4),
                              target: Tile(x: index, y: 0, z: 4),
                              screenDemandPx: 1500,
                              distanceToCamera: Float(index))
        }

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: candidates)

        assertNoOverlappingAllocations(plan.allocations)
        XCTAssertEqual(plan.allocations.count, 5)
        XCTAssertEqual(plan.pageSummaries.count, 2)
        XCTAssertEqual(plan.allocations.map(\.atlasDepth), Array(repeating: .depth1, count: 5))
        XCTAssertEqual(plan.downgradedAllocationCount, 0)
        XCTAssertEqual(plan.skippedAllocationCount, 0)
    }

    func testAllocatorCreatesSecondPageForFullPageDemandsInsteadOfDowngrading() throws {
        let first = try makeCandidate(index: 0,
                                      source: Tile(x: 0, y: 0, z: 2),
                                      target: Tile(x: 0, y: 0, z: 2),
                                      screenDemandPx: 3000,
                                      distanceToCamera: 0.0)
        let second = try makeCandidate(index: 1,
                                       source: Tile(x: 1, y: 0, z: 2),
                                       target: Tile(x: 1, y: 0, z: 2),
                                       screenDemandPx: 2800,
                                       distanceToCamera: 0.1)

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [first, second])

        assertNoOverlappingAllocations(plan.allocations)
        XCTAssertEqual(plan.allocations.count, 2)
        XCTAssertEqual(plan.allocations.map(\.pageIndex), [0, 1])
        XCTAssertEqual(plan.allocations.map(\.atlasDepth), [.depth0, .depth0])
        XCTAssertEqual(plan.downgradedAllocationCount, 0)
        XCTAssertEqual(plan.skippedAllocationCount, 0)
    }

    func testGlobeAtlasDebugSummaryCountsPagesSlotsAndHighResolutionFallbacks() throws {
        let candidates = try [
            makeCandidate(index: 0,
                          source: Tile(x: 4, y: 4, z: 3),
                          target: Tile(x: 16, y: 16, z: 5),
                          screenDemandPx: 1500,
                          distanceToCamera: 0.0),
            makeCandidate(index: 1,
                          source: Tile(x: 1, y: 0, z: 4),
                          target: Tile(x: 1, y: 0, z: 4),
                          screenDemandPx: 1500,
                          distanceToCamera: 1.0),
            makeCandidate(index: 2,
                          source: Tile(x: 2, y: 0, z: 4),
                          target: Tile(x: 2, y: 0, z: 4),
                          screenDemandPx: 1500,
                          distanceToCamera: 2.0),
            makeCandidate(index: 3,
                          source: Tile(x: 3, y: 0, z: 4),
                          target: Tile(x: 3, y: 0, z: 4),
                          screenDemandPx: 1500,
                          distanceToCamera: 3.0),
            makeCandidate(index: 4,
                          source: Tile(x: 4, y: 0, z: 4),
                          target: Tile(x: 4, y: 0, z: 4),
                          screenDemandPx: 1500,
                          distanceToCamera: 4.0)
        ]
        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: candidates)

        let summary = GlobeAtlasDebugSummary(plan: plan)

        XCTAssertEqual(summary.pageCount, 2)
        XCTAssertEqual(summary.allocationCount, 5)
        XCTAssertEqual(summary.downgradedAllocationCount, 0)
        XCTAssertEqual(summary.skippedAllocationCount, 0)
        XCTAssertEqual(summary.slotCount(depth: .depth1), 5)
        XCTAssertEqual(RendererDebugOverlayDrawer.makeAtlasDebugLines(summary: summary), [
            "atlas pages:2 alloc:5 down:0 skip:0",
            "atlas d0:0 d1:5 d2:0 d3:0 d4:0"
        ])
    }

    func testAllocatorExpandsBeyondFormerMaximumDepthFourCapacityWithoutSkips() throws {
        let candidates = try (0..<769).map { index in
            try makeCandidate(index: index,
                              source: Tile(x: index, y: 0, z: 10),
                              target: Tile(x: index, y: 0, z: 10),
                              screenDemandPx: 90,
                              distanceToCamera: Float(index))
        }

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: candidates)

        XCTAssertEqual(plan.allocations.count, 769)
        XCTAssertEqual(plan.skippedAllocationCount, 0)
        XCTAssertEqual(plan.pageSummaries.count, 4)
        XCTAssertEqual(Set(plan.allocations.map(\.atlasDepth)), [.depth4])
    }

    func testAllocatorCreatesOnePagePerFullPageDemandWithoutSkips() throws {
        let candidates = try (0..<8).map { index in
            try makeCandidate(index: index,
                              source: Tile(x: index, y: 0, z: 10),
                              target: Tile(x: index, y: 0, z: 10),
                              screenDemandPx: 3000,
                              distanceToCamera: Float(index))
        }

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: candidates)

        XCTAssertEqual(plan.allocations.count, 8)
        XCTAssertEqual(plan.pageSummaries.count, 8)
        XCTAssertEqual(plan.skippedAllocationCount, 0)
        XCTAssertEqual(plan.downgradedAllocationCount, 0)
        XCTAssertEqual(Set(plan.allocations.map(\.atlasDepth)), [.depth0])
    }

    func testDebugSummaryCountsDepthFourFallbackSlot() throws {
        let fallback = try makeCandidate(index: 0,
                                         source: Tile(x: 0, y: 0, z: 3),
                                         target: Tile(x: 0, y: 0, z: 5),
                                         screenDemandPx: 128,
                                         distanceToCamera: 0)

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [fallback])

        let summary = GlobeAtlasDebugSummary(plan: plan)

        XCTAssertEqual(summary.slotCount(depth: .depth4), 1)
    }

    func testGlobeAtlasDebugSummaryIncludesPageAllocationLayout() throws {
        let fallback = try makeCandidate(index: 0,
                                         source: Tile(x: 4, y: 2, z: 3),
                                         target: Tile(x: 17, y: 10, z: 5),
                                         screenDemandPx: 1700,
                                         distanceToCamera: 0.1)
        let exact = try makeCandidate(index: 1,
                                      source: Tile(x: 18, y: 10, z: 5),
                                      target: Tile(x: 18, y: 10, z: 5),
                                      screenDemandPx: 260,
                                      distanceToCamera: 0.2)
        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [exact, fallback])

        let summary = GlobeAtlasDebugSummary(plan: plan)

        XCTAssertEqual(summary.pages.count, 1)
        XCTAssertEqual(summary.pages[0].pageIndex, 0)
        XCTAssertEqual(summary.pages[0].allocations.count, 2)
        XCTAssertEqual(summary.pages[0].allocations[0].sourceTile, Tile(x: 4, y: 2, z: 3))
        XCTAssertEqual(summary.pages[0].allocations[0].targetTile, Tile(x: 17, y: 10, z: 5))
        XCTAssertEqual(summary.pages[0].allocations[0].atlasDepth, .depth1)
        XCTAssertEqual(summary.pages[0].allocations[0].cellSizePx, 2048)
        XCTAssertTrue(summary.pages[0].allocations[0].isFallback)
        XCTAssertEqual(summary.pages[0].allocations[1].sourceTile, Tile(x: 18, y: 10, z: 5))
        XCTAssertEqual(summary.pages[0].allocations[1].targetTile, Tile(x: 18, y: 10, z: 5))
        XCTAssertEqual(summary.pages[0].allocations[1].atlasDepth, .depth3)
        XCTAssertEqual(summary.pages[0].allocations[1].cellSizePx, 512)
        XCTAssertFalse(summary.pages[0].allocations[1].isFallback)
    }

    func testTextureTreeRejectsParentSlotAfterChildSlotAllocated() {
        let tree = GlobeTileTextureTree()

        XCTAssertNotNil(tree.addNewValue(value: TextureValue(), depth: 1))
        XCTAssertNil(tree.addNewValue(value: TextureValue(), depth: 0))
    }

    func testAllocatorKeepsMixedDemandSetAtEachDesiredDepthWithoutOverlaps() throws {
        let large = try makeCandidate(index: 0,
                                      source: Tile(x: 0, y: 0, z: 3),
                                      target: Tile(x: 0, y: 0, z: 3),
                                      screenDemandPx: 1500,
                                      distanceToCamera: 0.0)
        let small = try (1...13).map { index in
            try makeCandidate(index: index,
                              source: Tile(x: index, y: 0, z: 5),
                              target: Tile(x: index, y: 0, z: 5),
                              screenDemandPx: 900,
                              distanceToCamera: Float(index))
        }

        let plan = GlobeAtlasPlacementPlanner(pageSizePx: 4096)
            .plan(candidates: [large] + small)

        assertNoOverlappingAllocations(plan.allocations)
        XCTAssertEqual(plan.allocations.count, 14)
        XCTAssertEqual(plan.allocations.first?.atlasDepth, .depth1)
        XCTAssertEqual(Array(plan.allocations.dropFirst()).map(\.atlasDepth), Array(repeating: .depth2, count: 13))
        XCTAssertEqual(plan.downgradedAllocationCount, 0)
        XCTAssertEqual(plan.skippedAllocationCount, 0)
    }

    func testMakeCandidateUsesTargetTileFootprintNotSourceTileZoom() throws {
        let source = Tile(x: 4, y: 2, z: 3)
        let target = Tile(x: 17, y: 10, z: 5)
        let metalTile = MetalTile(tile: source, tileBuffers: try makeTileBuffers())
        let placeTile = PlaceTile(metalTile: metalTile,
                                  placeIn: VisibleTile(tile: target),
                                  lodKind: .retainedReplacement)

        let candidate = GlobeAtlasPlacementPlanner.makeCandidateForTesting(
            placementIndex: 0,
            placeTile: placeTile,
            screenBoundsPx: CGRect(x: 100, y: 100, width: 1300, height: 800),
            pageSizePx: 4096
        )

        XCTAssertEqual(candidate.placeTile.metalTile.tile, source)
        XCTAssertEqual(candidate.placeTile.placeIn.tile, target)
        XCTAssertEqual(candidate.screenDemandPx, 1300, accuracy: 0.1)
        XCTAssertEqual(candidate.desiredDepth, .depth1)
        XCTAssertTrue(candidate.isFallback)
    }

    func testMakeCandidatesUsesTargetTileForFallbackFootprint() throws {
        let source = Tile(x: 4, y: 4, z: 3)
        let target = Tile(x: 16, y: 16, z: 5)
        let metalTile = MetalTile(tile: source, tileBuffers: try makeTileBuffers())
        let fallback = PlaceTile(metalTile: metalTile,
                                 placeIn: VisibleTile(tile: target),
                                 lodKind: .retainedReplacement)
        let exact = PlaceTile(metalTile: MetalTile(tile: target, tileBuffers: try makeTileBuffers()),
                              placeIn: VisibleTile(tile: target),
                              lodKind: .exact)
        let frameContext = makeGlobeFrameContext()
        let planner = GlobeAtlasPlacementPlanner(pageSizePx: 4096)

        let fallbackCandidate = try XCTUnwrap(planner.makeCandidates(placeTiles: [fallback],
                                                                     frameContext: frameContext).first)
        let exactCandidate = try XCTUnwrap(planner.makeCandidates(placeTiles: [exact],
                                                                  frameContext: frameContext).first)

        XCTAssertEqual(fallbackCandidate.placeTile.metalTile.tile, source)
        XCTAssertEqual(fallbackCandidate.placeTile.placeIn.tile, target)
        XCTAssertEqual(fallbackCandidate.screenDemandPx, exactCandidate.screenDemandPx, accuracy: 0.1)
        XCTAssertLessThanOrEqual(fallbackCandidate.screenDemandPx, 1024)
        XCTAssertEqual(fallbackCandidate.desiredDepth, exactCandidate.desiredDepth)
        XCTAssertTrue(fallbackCandidate.distanceToCamera.isFinite)
        XCTAssertLessThan(fallbackCandidate.distanceToCamera, Float.greatestFiniteMagnitude)
        XCTAssertTrue(fallbackCandidate.isFallback)
    }

    func testScreenFootprintIgnoresProjectedSamplesThatFailHorizonVisibility() {
        let footprint = GlobeAtlasPlacementPlanner.screenFootprintForTesting(
            projectedSamples: [
                (position: SIMD2<Float>(100, 100), depth: 0.1, passesHorizon: false),
                (position: SIMD2<Float>(400, 300), depth: 0.2, passesHorizon: false)
            ],
            viewport: SIMD2<Float>(1024, 768)
        )

        XCTAssertNil(footprint)
    }

    func testScreenFootprintBuildsBoundsFromOnlyHorizonVisibleSamples() throws {
        let footprint = try XCTUnwrap(GlobeAtlasPlacementPlanner.screenFootprintForTesting(
            projectedSamples: [
                (position: SIMD2<Float>(100, 100), depth: 0.1, passesHorizon: false),
                (position: SIMD2<Float>(400, 300), depth: 0.2, passesHorizon: true),
                (position: SIMD2<Float>(700, 500), depth: 0.3, passesHorizon: true)
            ],
            viewport: SIMD2<Float>(1024, 768)
        ))

        XCTAssertEqual(footprint.minX, 400, accuracy: 0.1)
        XCTAssertEqual(footprint.minY, 300, accuracy: 0.1)
        XCTAssertEqual(footprint.width, 300, accuracy: 0.1)
        XCTAssertEqual(footprint.height, 200, accuracy: 0.1)
    }

    private func makeCandidate(index: Int,
                               source: Tile,
                               target: Tile,
                               screenDemandPx: Float,
                               distanceToCamera: Float) throws -> GlobeAtlasCandidate {
        let metalTile = MetalTile(tile: source, tileBuffers: try makeTileBuffers())
        let placeTile = PlaceTile(metalTile: metalTile,
                                  placeIn: VisibleTile(tile: target),
                                  lodKind: source == target ? .exact : .retainedReplacement)
        return GlobeAtlasCandidate(placementIndex: index,
                                   placeTile: placeTile,
                                   screenDemandPx: screenDemandPx,
                                   distanceToCamera: distanceToCamera,
                                   desiredDepth: GlobeAtlasSlotDepth.desired(forScreenDemandPx: screenDemandPx,
                                                                             pageSizePx: 4096))
    }

    private func makeTileBuffers() throws -> TileBuffers {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is required for MetalTile test fixture.")
        }
        let value: UInt32 = 0
        let buffer = device.makeBuffer(bytes: [value], length: MemoryLayout<UInt32>.stride)!
        let ground = TileBuffers.GeometryLayer(verticesBuffer: buffer,
                                               indicesBuffer: buffer,
                                               stylesBuffer: buffer,
                                               overviewStyleMaskBuffer: buffer,
                                               indicesCount: 0,
                                               verticesCount: 0)
        let extruded = TileBuffers.Extruded(verticesBuffer: buffer,
                                            indicesBuffer: buffer,
                                            stylesBuffer: buffer,
                                            indicesCount: 0,
                                            verticesCount: 0)
        let phases = RoadGeometryPhases(shadow: ground,
                                        casing: ground,
                                        fill: ground,
                                        detail: ground,
                                        overlay: ground)
        let roads = RoadStructureBuckets(tunnel: phases,
                                         ground: phases,
                                         bridge: phases)
        return TileBuffers(ground: ground,
                           roads: roads,
                           bridgeOverlay: ground,
                           extruded: extruded,
                           textLabels: TileBuffers.TextLabels(placementInputs: [],
                                                               labelsByStyleRuns: [],
                                                               poiIconRuns: []),
                           roadLabels: TileBuffers.RoadLabels(pathInputs: [],
                                                              pathRanges: [],
                                                              pathLabels: [],
                                                              labelStyle: nil,
                                                              localGlyphVerticesBuffer: nil,
                                                              localGlyphVertexCount: 0,
                                                              glyphBounds: [],
                                                              glyphBoundRanges: [],
                                                              sizes: [],
                                                              anchorRanges: [],
                                                              anchors: []))
    }

    private func makeGlobeFrameContext() -> FrameContext {
        let settings = ImmersiveMapSettings.default
        let cameraState = ImmersiveMapCameraState(centerWorldMercator: SIMD2<Double>(0.5, 0.5),
                                                  zoom: 5.0,
                                                  bearing: 0,
                                                  pitch: 0)
        let diagnostics = FrameDiagnostics(frameIndex: 0, frameTime: 0)
        return FrameContext(frameIndex: 0,
                            time: 0,
                            deltaTime: 0,
                            drawSize: CGSize(width: 1024, height: 768),
                            viewport: SIMD2<Float>(1024, 768),
                            cameraMatrices: .identity,
                            cameraEye: SIMD3<Float>(0, 0, 1),
                            qualityTier: .low,
                            commandBuffer: nil,
                            drawable: nil,
                            services: FrameContextServices(diagnostics: diagnostics,
                                                           settings: settings,
                                                           now: Date(timeIntervalSince1970: 0)),
                            mapCameraState: cameraState,
                            resolvedPresentation: PresentationStateResolver.resolve(cameraState: cameraState,
                                                                                   settings: settings.presentation,
                                                                                   forcedRenderSurfaceMode: .spherical),
                            diagnostics: diagnostics)
    }

    private func assertNoOverlappingAllocations(_ allocations: [GlobeAtlasAllocation],
                                                file: StaticString = #filePath,
                                                line: UInt = #line) {
        for leftIndex in allocations.indices {
            for rightIndex in allocations.index(after: leftIndex)..<allocations.endIndex {
                let left = allocations[leftIndex]
                let right = allocations[rightIndex]
                guard left.pageIndex == right.pageIndex else {
                    continue
                }
                XCTAssertFalse(atlasRect(left).intersects(atlasRect(right)),
                               "Overlapping atlas allocations: \(left) and \(right)",
                               file: file,
                               line: line)
            }
        }
    }

    private func atlasRect(_ allocation: GlobeAtlasAllocation) -> AtlasRect {
        let commonDepth = Int(GlobeAtlasSlotDepth.depth4.rawValue)
        let depth = Int(allocation.atlasDepth.rawValue)
        let scale = 1 << (commonDepth - depth)
        let minX = Int(allocation.placedPosition.x) * scale
        let minY = Int(allocation.placedPosition.y) * scale
        return AtlasRect(minX: minX,
                         minY: minY,
                         maxX: minX + scale,
                         maxY: minY + scale)
    }
}

private struct AtlasRect {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    func intersects(_ other: AtlasRect) -> Bool {
        minX < other.maxX &&
            maxX > other.minX &&
            minY < other.maxY &&
            maxY > other.minY
    }
}
