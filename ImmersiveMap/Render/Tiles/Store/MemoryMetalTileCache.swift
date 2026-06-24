// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

private final class TileCacheKey: NSObject {
    let tile: Tile
    
    init(_ tile: Tile) {
        self.tile = tile
    }
    
    override var hash: Int {
        tile.hashValue
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TileCacheKey else {
            return false
        }
        return tile == other.tile
    }
}

class MemoryMetalTileCache {
    private let cache: NSCache<TileCacheKey, MetalTile>
    private let cacheDelegate: MemoryMetalTileCacheDelegate
    private let costLimit: Int
    private let stateLock = NSLock()
    private let tileTraceRecorder: TileTraceRecorder

    private var trackedCostByTile: [Tile: Int] = [:]
    private var trackedTotalCost = 0
    private var isRemovingAll = false
    
    init(maxCacheSizeInBytes: Int, tileTraceRecorder: TileTraceRecorder) {
        self.cacheDelegate = MemoryMetalTileCacheDelegate()
        self.costLimit = maxCacheSizeInBytes
        self.tileTraceRecorder = tileTraceRecorder
        self.cache = NSCache<TileCacheKey, MetalTile>()
        self.cache.totalCostLimit = maxCacheSizeInBytes
        self.cache.delegate = cacheDelegate
        self.cacheDelegate.onEvict = { [weak self] object in
            self?.recordEviction(for: object)
        }
    }
    
    func setTileData(tile: MetalTile, forKey key: Tile) {
        let estimatedCost = estimateTileByteSize(tile)
        let snapshot = updateTrackedCost(for: key, cost: estimatedCost)
        cache.setObject(tile, forKey: TileCacheKey(key), cost: estimatedCost)
        tileTraceRecorder.record(.tileMemoryCacheSet(key,
                                                     cost: estimatedCost,
                                                     replacedCost: snapshot.replacedCost,
                                                     trackedCost: snapshot.totalCost,
                                                     trackedCount: snapshot.count,
                                                     costLimit: costLimit))
    }
    
    func getTile(forKey key: Tile) -> MetalTile? {
        let tile = cache.object(forKey: TileCacheKey(key))
        let snapshot = trackedSnapshot(for: key)
        tileTraceRecorder.record(.tileMemoryCacheGet(key,
                                                     hit: tile != nil,
                                                     knownCost: snapshot.knownCost,
                                                     trackedCost: snapshot.totalCost,
                                                     trackedCount: snapshot.count,
                                                     costLimit: costLimit))
        return tile
    }

    func removeAll() {
        let snapshot = beginRemoveAllTrackedCosts()
        cache.removeAllObjects()
        finishRemoveAllTrackedCosts()
        tileTraceRecorder.record(.event("tile_memory_cache_remove_all",
                                        fields: [
                                            "removedCost": .int(snapshot.totalCost),
                                            "removedCount": .int(snapshot.count),
                                            "costLimit": .int(costLimit)
                                        ]))
    }

    private func updateTrackedCost(for tile: Tile,
                                   cost: Int) -> (replacedCost: Int?, totalCost: Int, count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let replacedCost = trackedCostByTile[tile]
        if let replacedCost {
            trackedTotalCost -= replacedCost
        }
        trackedCostByTile[tile] = cost
        trackedTotalCost += cost
        return (replacedCost, trackedTotalCost, trackedCostByTile.count)
    }

    private func trackedSnapshot(for tile: Tile) -> (knownCost: Int?, totalCost: Int, count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        return (trackedCostByTile[tile], trackedTotalCost, trackedCostByTile.count)
    }

    private func removeTrackedCost(for tile: Tile) -> (cost: Int?, totalCost: Int, count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let cost = trackedCostByTile.removeValue(forKey: tile)
        if let cost {
            trackedTotalCost -= cost
        }
        return (cost, trackedTotalCost, trackedCostByTile.count)
    }

    private func beginRemoveAllTrackedCosts() -> (totalCost: Int, count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let snapshot = (trackedTotalCost, trackedCostByTile.count)
        trackedCostByTile.removeAll(keepingCapacity: false)
        trackedTotalCost = 0
        isRemovingAll = true
        return snapshot
    }

    private func finishRemoveAllTrackedCosts() {
        stateLock.lock()
        isRemovingAll = false
        stateLock.unlock()
    }

    private func recordEviction(for object: Any) {
        guard let metalTile = object as? MetalTile else {
            return
        }

        let tile = metalTile.tile
        guard shouldRecordEviction() else {
            return
        }
        let snapshot = removeTrackedCost(for: tile)
        tileTraceRecorder.record(.tileMemoryCacheEvict(tile,
                                                       cost: snapshot.cost,
                                                       trackedCost: snapshot.totalCost,
                                                       trackedCount: snapshot.count,
                                                       costLimit: costLimit))
    }

    private func shouldRecordEviction() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        return isRemovingAll == false
    }
    
    private func estimateTileByteSize(_ tile: MetalTile) -> Int {
        let tileBuffers = tile.tileBuffers
        
        let layers = [tileBuffers.ground]
            + tileBuffers.roads.drawOrderBuckets.flatMap(\.drawOrderLayers)
            + [tileBuffers.bridgeOverlay]
        let geometrySize = layers.reduce(0) { partial, layer in
            partial + layer.verticesBuffer.allocatedSize
                + layer.indicesBuffer.allocatedSize
                + layer.stylesBuffer.allocatedSize
                + layer.overviewStyleMaskBuffer.allocatedSize
        }
        let extrudedSize = tileBuffers.extruded.verticesBuffer.allocatedSize
            + tileBuffers.extruded.indicesBuffer.allocatedSize
            + tileBuffers.extruded.stylesBuffer.allocatedSize
        return geometrySize + extrudedSize
    }
}

private final class MemoryMetalTileCacheDelegate: NSObject, NSCacheDelegate {
    var onEvict: ((Any) -> Void)?

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        onEvict?(obj)
    }
}
