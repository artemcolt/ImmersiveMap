// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

enum GlobeAtlasSlotDepth: UInt8, CaseIterable, Comparable, Hashable {
    case depth0 = 0
    case depth1 = 1
    case depth2 = 2
    case depth3 = 3
    case depth4 = 4

    static func < (lhs: GlobeAtlasSlotDepth, rhs: GlobeAtlasSlotDepth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func cellSize(pageSizePx: Int) -> Int {
        pageSizePx / (1 << Int(rawValue))
    }

    static func desired(forScreenDemandPx screenDemandPx: Float,
                        pageSizePx: Int,
                        qualityScale: Float = 1.0) -> GlobeAtlasSlotDepth {
        let demand = max(1.0, screenDemandPx * max(0.25, qualityScale))
        for depth in GlobeAtlasSlotDepth.allCases.reversed() {
            if Float(depth.cellSize(pageSizePx: pageSizePx)) >= demand {
                return depth
            }
        }
        return .depth0
    }
}

struct GlobeAtlasCandidate: Hashable {
    let placementIndex: Int
    let placeTile: PlaceTile
    let layer: GlobeTextureLayer
    let screenDemandPx: Float
    let distanceToCamera: Float
    let desiredDepth: GlobeAtlasSlotDepth

    var isFallback: Bool {
        placeTile.isReplacement()
    }
}

struct GlobeAtlasAllocation: Hashable {
    let candidate: GlobeAtlasCandidate
    let pageIndex: Int
    let placedPosition: PlacedPos
    let atlasDepth: GlobeAtlasSlotDepth
    let cellSizePx: Int

    var placeTile: PlaceTile {
        candidate.placeTile
    }
}

struct GlobeAtlasPageSummary: Equatable {
    let pageIndex: Int
    let allocatedSlotCount: Int
}

struct GlobeAtlasPlan: Equatable {
    let allocations: [GlobeAtlasAllocation]
    let pageSummaries: [GlobeAtlasPageSummary]
    let downgradedAllocationCount: Int
    let skippedAllocationCount: Int

    static let empty = GlobeAtlasPlan(allocations: [],
                                      pageSummaries: [],
                                      downgradedAllocationCount: 0,
                                      skippedAllocationCount: 0)
}

struct GlobeAtlasDebugSummary: Equatable {
    let pageCount: Int
    let allocationCount: Int
    let baseAllocationCount: Int
    let detailAllocationCount: Int
    let downgradedAllocationCount: Int
    let skippedAllocationCount: Int
    let slotCountsByDepth: [GlobeAtlasSlotDepth: Int]
    let fallbackHighResolutionCount: Int

    init(plan: GlobeAtlasPlan) {
        pageCount = plan.pageSummaries.count
        allocationCount = plan.allocations.count
        baseAllocationCount = plan.allocations.filter { $0.candidate.layer == .base }.count
        detailAllocationCount = plan.allocations.filter { $0.candidate.layer == .detail }.count
        downgradedAllocationCount = plan.downgradedAllocationCount
        skippedAllocationCount = plan.skippedAllocationCount

        slotCountsByDepth = Dictionary(grouping: plan.allocations, by: \.atlasDepth)
            .mapValues(\.count)
        fallbackHighResolutionCount = plan.allocations.reduce(into: 0) { count, allocation in
            guard allocation.candidate.isFallback,
                  allocation.atlasDepth != .depth4,
                  allocation.atlasDepth.rawValue <= allocation.candidate.desiredDepth.rawValue else {
                return
            }
            count += 1
        }
    }

    func slotCount(depth: GlobeAtlasSlotDepth) -> Int {
        slotCountsByDepth[depth] ?? 0
    }
}
