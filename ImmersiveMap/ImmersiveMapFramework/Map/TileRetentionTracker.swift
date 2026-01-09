//
//  TileRetentionTracker.swift
//  ImmersiveMap
//
//  Created by Artem on 1/20/26.
//

import Foundation

final class TileRetentionTracker {
    struct TrackedTile {
        let tile: Tile
        let isRetained: Bool
    }

    private struct Entry {
        var lastSeen: TimeInterval
        var isRetained: Bool
    }

    private let holdSeconds: TimeInterval
    private var entries: [Tile: Entry] = [:]

    init(holdSeconds: TimeInterval) {
        self.holdSeconds = holdSeconds
    }

    func update(visibleTiles: [Tile], now: TimeInterval) -> [TrackedTile] {
        let visibleSet = Set(visibleTiles)

        for tile in visibleTiles {
            entries[tile] = Entry(lastSeen: now, isRetained: false)
        }

        var expired: [Tile] = []
        for (tile, entry) in entries {
            if visibleSet.contains(tile) {
                continue
            }
            if now - entry.lastSeen > holdSeconds {
                expired.append(tile)
            } else {
                entries[tile] = Entry(lastSeen: entry.lastSeen, isRetained: true)
            }
        }

        if expired.isEmpty == false {
            for tile in expired {
                entries.removeValue(forKey: tile)
            }
        }

        var result: [TrackedTile] = []
        result.reserveCapacity(entries.count)
        for tile in visibleTiles {
            result.append(TrackedTile(tile: tile, isRetained: false))
        }

        let retainedTiles = entries.compactMap { (tile, entry) -> TrackedTile? in
            if visibleSet.contains(tile) || entry.isRetained == false {
                return nil
            }
            return TrackedTile(tile: tile, isRetained: true)
        }
        .sorted { lhs, rhs in
            let left = entries[lhs.tile]
            let right = entries[rhs.tile]
            let leftTime = left?.lastSeen ?? 0
            let rightTime = right?.lastSeen ?? 0
            if leftTime != rightTime {
                return leftTime > rightTime
            }
            if lhs.tile.z != rhs.tile.z {
                return lhs.tile.z > rhs.tile.z
            }
            if lhs.tile.x != rhs.tile.x {
                return lhs.tile.x < rhs.tile.x
            }
            if lhs.tile.y != rhs.tile.y {
                return lhs.tile.y < rhs.tile.y
            }
            return lhs.tile.loop < rhs.tile.loop
        }

        result.append(contentsOf: retainedTiles)
        return result
    }
}
