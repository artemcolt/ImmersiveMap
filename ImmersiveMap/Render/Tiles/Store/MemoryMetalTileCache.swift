// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

class MemoryMetalTileCache {
    private var cache: LRUMemoryCache<Tile, MetalTile>
    private let costLimit: Int
    private let stateLock = NSLock()
    private let tileTraceRecorder: TileTraceRecorder
    
    init(maxCacheSizeInBytes: Int, tileTraceRecorder: TileTraceRecorder) {
        self.costLimit = maxCacheSizeInBytes
        self.tileTraceRecorder = tileTraceRecorder
        self.cache = LRUMemoryCache(costLimit: maxCacheSizeInBytes)
    }
    
    func setTileData(tile: MetalTile, forKey key: Tile) {
        let estimatedCost = estimateTileByteSize(tile)
        let mutation = setTile(tile, forKey: key, cost: estimatedCost)
        tileTraceRecorder.record(.tileMemoryCacheSet(key,
                                                     cost: estimatedCost,
                                                     replacedCost: mutation.replacedCost,
                                                     trackedCost: mutation.totalCost,
                                                     trackedCount: mutation.count,
                                                     costLimit: costLimit))
        for evictedEntry in mutation.evictedEntries {
            tileTraceRecorder.record(.tileMemoryCacheEvict(evictedEntry.key,
                                                           cost: evictedEntry.cost,
                                                           trackedCost: mutation.totalCost,
                                                           trackedCount: mutation.count,
                                                           costLimit: costLimit))
        }
    }
    
    func getTile(forKey key: Tile) -> MetalTile? {
        let snapshot = getTileAndSnapshot(forKey: key)
        tileTraceRecorder.record(.tileMemoryCacheGet(key,
                                                     hit: snapshot.tile != nil,
                                                     knownCost: snapshot.knownCost,
                                                     trackedCost: snapshot.totalCost,
                                                     trackedCount: snapshot.count,
                                                     costLimit: costLimit))
        return snapshot.tile
    }

    func removeAll() {
        let snapshot = removeAllTiles()
        tileTraceRecorder.record(.event("tile_memory_cache_remove_all",
                                        fields: [
                                            "removedCost": .int(snapshot.totalCost),
                                            "removedCount": .int(snapshot.count),
                                            "costLimit": .int(costLimit)
                                        ]))
    }

    private func setTile(_ tile: MetalTile,
                         forKey key: Tile,
                         cost: Int) -> (replacedCost: Int?,
                                        evictedEntries: [LRUMemoryCache<Tile, MetalTile>.Entry],
                                        totalCost: Int,
                                        count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let replacedCost = cache.cost(forKey: key)
        let evictedEntries = cache.setValue(tile, forKey: key, cost: cost) ?? []
        return (replacedCost, evictedEntries, cache.totalCost, cache.count)
    }

    private func getTileAndSnapshot(forKey key: Tile) -> (tile: MetalTile?,
                                                          knownCost: Int?,
                                                          totalCost: Int,
                                                          count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let tile = cache.value(forKey: key)
        return (tile, cache.cost(forKey: key), cache.totalCost, cache.count)
    }

    private func removeAllTiles() -> (totalCost: Int, count: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let snapshot = (cache.totalCost, cache.count)
        _ = cache.removeAll()
        return snapshot
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
