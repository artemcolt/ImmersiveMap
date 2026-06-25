// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct TileLoadingPhaseSnapshot: Equatable {
    let inFlight: Int
    let completed: Int
    let failed: Int
}

enum TileLoadingTileStatus: Equatable {
    case queued
    case loading
    case parsing
    case ready
    case failed
}

struct TileLoadingStatusTileSnapshot: Equatable {
    let tile: Tile
    let status: TileLoadingTileStatus
    let progress: Double
    let detail: String
}

struct TileLoadingStatusSnapshot: Equatable {
    let requested: Int
    let deduplicated: Int
    let activeLoads: Int
    let scheduled: Int
    let network: TileLoadingPhaseSnapshot
    let parsing: TileLoadingPhaseSnapshot
    let totalCompleted: Int
    let totalFailed: Int
    let networkBytes: Int
    let latestNetworkTile: Tile?
    let latestParsingTile: Tile?
    let latestFailure: String?
    let tiles: [TileLoadingStatusTileSnapshot]

    var lines: [String] {
        guard requested > 0 || activeLoads > 0 || scheduled > 0 || totalCompleted > 0 || totalFailed > 0 else {
            return []
        }

        var output = [
            "tiles req:\(requested) dedup:\(deduplicated) active:\(activeLoads) scheduled:\(scheduled)",
            "network in:\(network.inFlight) done:\(network.completed) fail:\(network.failed) bytes:\(networkBytes)",
            "parse in:\(parsing.inFlight) done:\(parsing.completed) fail:\(parsing.failed)",
            "total done:\(totalCompleted) fail:\(totalFailed)"
        ]

        let currentNetwork = latestNetworkTile.map { "net:\(Self.tileDescription($0))" }
        let currentParsing = latestParsingTile.map { "parse:\(Self.tileDescription($0))" }
        let current = [currentNetwork, currentParsing].compactMap { $0 }.joined(separator: " ")
        if current.isEmpty == false {
            output.append("current \(current)")
        }
        if let latestFailure {
            output.append("last failure: \(latestFailure)")
        }
        return output
    }

    private static func tileDescription(_ tile: Tile) -> String {
        "z\(tile.z)/\(tile.x)/\(tile.y)"
    }
}

final class TileLoadingStatusReporter {
    private struct PhaseCounters {
        var inFlight = 0
        var completed = 0
        var failed = 0

        var snapshot: TileLoadingPhaseSnapshot {
            TileLoadingPhaseSnapshot(inFlight: inFlight,
                                     completed: completed,
                                     failed: failed)
        }
    }

    private struct TileRecord {
        var status: TileLoadingTileStatus
        var progress: Double
        var detail: String
        var sequence: UInt64
    }

    private let queue = DispatchQueue(label: "ImmersiveMap.TileLoadingStatusReporter")
    private var requested = 0
    private var deduplicated = 0
    private var activeLoads = 0
    private var scheduled = 0
    private var network = PhaseCounters()
    private var parsing = PhaseCounters()
    private var totalCompleted = 0
    private var totalFailed = 0
    private var networkBytes = 0
    private var activeNetworkTiles: Set<Tile> = []
    private var activeParsingTiles: Set<Tile> = []
    private var latestNetworkTile: Tile?
    private var latestParsingTile: Tile?
    private var latestFailure: String?
    private var currentDemand: Set<Tile> = []
    private var displayedTiles: Set<Tile> = []
    private var tileRecords: [Tile: TileRecord] = [:]
    private var sequence: UInt64 = 0

    func recordDemand(input: Int, deduplicated: Int, tiles: [Tile]) {
        queue.sync {
            self.requested = input
            self.deduplicated = deduplicated
            currentDemand = Set(tiles)
            pruneInactiveStaleTiles()
        }
    }

    func recordDisplayedTiles(_ tiles: [Tile]) {
        queue.sync {
            displayedTiles = Set(tiles)
            for tile in tiles {
                guard shouldCreateDisplayedRecord(for: tile) else {
                    continue
                }
                updateTile(tile,
                           status: .ready,
                           progress: 1,
                           detail: "displayed")
            }
            pruneInactiveStaleTiles()
        }
    }

    func recordLoadScheduled(tile: Tile) {
        queue.sync {
            scheduled += 1
            updateTile(tile,
                       status: .queued,
                       progress: 0.1,
                       detail: "queued")
        }
    }

    func recordLoadStarted(tile: Tile) {
        queue.sync {
            activeLoads += 1
            updateTile(tile,
                       status: .loading,
                       progress: 0.35,
                       detail: "network")
        }
    }

    func recordLoadCompleted(tile: Tile) {
        queue.sync {
            activeLoads = max(0, activeLoads - 1)
            totalCompleted += 1
            updateTile(tile,
                       status: .ready,
                       progress: 1,
                       detail: "ready")
            pruneInactiveStaleTiles()
        }
    }

    func recordLoadFailed(tile: Tile, reason: String) {
        queue.sync {
            activeLoads = max(0, activeLoads - 1)
            totalFailed += 1
            latestFailure = reason
            updateTile(tile,
                       status: .failed,
                       progress: 1,
                       detail: reason)
            pruneInactiveStaleTiles()
        }
    }

    func recordNetworkStarted(tile: Tile) {
        queue.sync {
            network.inFlight += 1
            activeNetworkTiles.insert(tile)
            latestNetworkTile = tile
            updateTile(tile,
                       status: .loading,
                       progress: 0.35,
                       detail: "network")
        }
    }

    func recordNetworkSucceeded(tile: Tile, bytes: Int) {
        queue.sync {
            network.inFlight = max(0, network.inFlight - 1)
            network.completed += 1
            networkBytes += bytes
            activeNetworkTiles.remove(tile)
            updateTile(tile,
                       status: .loading,
                       progress: 0.55,
                       detail: "\(bytes) bytes")
            refreshLatestNetworkTile()
        }
    }

    func recordNetworkFailed(tile: Tile, reason: String) {
        queue.sync {
            network.inFlight = max(0, network.inFlight - 1)
            network.failed += 1
            activeNetworkTiles.remove(tile)
            latestFailure = reason
            updateTile(tile,
                       status: .failed,
                       progress: 1,
                       detail: reason)
            refreshLatestNetworkTile()
        }
    }

    func recordParsingStarted(tile: Tile) {
        queue.sync {
            parsing.inFlight += 1
            activeParsingTiles.insert(tile)
            latestParsingTile = tile
            updateTile(tile,
                       status: .parsing,
                       progress: 0.7,
                       detail: "parse")
        }
    }

    func recordParsingSucceeded(tile: Tile) {
        queue.sync {
            parsing.inFlight = max(0, parsing.inFlight - 1)
            parsing.completed += 1
            activeParsingTiles.remove(tile)
            updateTile(tile,
                       status: .parsing,
                       progress: 0.85,
                       detail: "materialize")
            refreshLatestParsingTile()
        }
    }

    func recordParsingFailed(tile: Tile, reason: String) {
        queue.sync {
            parsing.inFlight = max(0, parsing.inFlight - 1)
            parsing.failed += 1
            activeParsingTiles.remove(tile)
            latestFailure = reason
            updateTile(tile,
                       status: .failed,
                       progress: 1,
                       detail: reason)
            refreshLatestParsingTile()
        }
    }

    func snapshot() -> TileLoadingStatusSnapshot {
        queue.sync {
            let tiles = tileRecords
                .filter { tile, record in
                    shouldIncludeTile(tile, record: record)
                }
                .map { tile, record in
                    (
                        snapshot: TileLoadingStatusTileSnapshot(tile: tile,
                                                                status: record.status,
                                                                progress: record.progress,
                                                                detail: record.detail),
                        sequence: record.sequence
                    )
                }
                .sorted(by: Self.shouldPlaceTileBefore)
                .map(\.snapshot)
            return TileLoadingStatusSnapshot(requested: requested,
                                             deduplicated: deduplicated,
                                             activeLoads: activeLoads,
                                             scheduled: scheduled,
                                             network: network.snapshot,
                                             parsing: parsing.snapshot,
                                             totalCompleted: totalCompleted,
                                             totalFailed: totalFailed,
                                             networkBytes: networkBytes,
                                             latestNetworkTile: latestNetworkTile,
                                             latestParsingTile: latestParsingTile,
                                             latestFailure: latestFailure,
                                             tiles: Array(tiles))
        }
    }

    private func updateTile(_ tile: Tile,
                            status: TileLoadingTileStatus,
                            progress: Double,
                            detail: String) {
        sequence &+= 1
        tileRecords[tile] = TileRecord(status: status,
                                       progress: min(max(progress, 0), 1),
                                       detail: detail,
                                       sequence: sequence)
    }

    private func pruneInactiveStaleTiles() {
        tileRecords = tileRecords.filter { tile, record in
            shouldIncludeTile(tile, record: record)
        }
    }

    private func refreshLatestNetworkTile() {
        latestNetworkTile = latestActiveTile(in: activeNetworkTiles)
    }

    private func refreshLatestParsingTile() {
        latestParsingTile = latestActiveTile(in: activeParsingTiles)
    }

    private func latestActiveTile(in tiles: Set<Tile>) -> Tile? {
        tiles.max { lhs, rhs in
            let lhsSequence = tileRecords[lhs]?.sequence ?? 0
            let rhsSequence = tileRecords[rhs]?.sequence ?? 0
            if lhsSequence != rhsSequence {
                return lhsSequence < rhsSequence
            }
            if lhs.z != rhs.z {
                return lhs.z < rhs.z
            }
            if lhs.x != rhs.x {
                return lhs.x > rhs.x
            }
            return lhs.y > rhs.y
        }
    }

    private func shouldIncludeTile(_ tile: Tile, record: TileRecord) -> Bool {
        currentDemand.contains(tile) || displayedTiles.contains(tile) || Self.isActiveResourceStatus(record.status)
    }

    private func shouldCreateDisplayedRecord(for tile: Tile) -> Bool {
        guard let record = tileRecords[tile] else {
            return true
        }
        return Self.isActiveResourceStatus(record.status) == false
    }

    private static func isActiveResourceStatus(_ status: TileLoadingTileStatus) -> Bool {
        switch status {
        case .loading, .parsing:
            return true
        case .queued, .ready, .failed:
            return false
        }
    }

    private static func shouldPlaceTileBefore(
        _ lhs: (snapshot: TileLoadingStatusTileSnapshot, sequence: UInt64),
        _ rhs: (snapshot: TileLoadingStatusTileSnapshot, sequence: UInt64)
    ) -> Bool {
        let lhsPriority = priority(lhs.snapshot.status)
        let rhsPriority = priority(rhs.snapshot.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        if lhs.sequence != rhs.sequence {
            return lhs.sequence > rhs.sequence
        }
        if lhs.snapshot.tile.z != rhs.snapshot.tile.z {
            return lhs.snapshot.tile.z > rhs.snapshot.tile.z
        }
        if lhs.snapshot.tile.x != rhs.snapshot.tile.x {
            return lhs.snapshot.tile.x < rhs.snapshot.tile.x
        }
        return lhs.snapshot.tile.y < rhs.snapshot.tile.y
    }

    private static func priority(_ status: TileLoadingTileStatus) -> Int {
        switch status {
        case .loading:
            return 0
        case .parsing:
            return 1
        case .queued:
            return 2
        case .failed:
            return 3
        case .ready:
            return 4
        }
    }
}
