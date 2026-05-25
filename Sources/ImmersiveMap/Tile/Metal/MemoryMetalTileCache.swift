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
    
    init(maxCacheSizeInBytes: Int) {
        self.cache = NSCache<TileCacheKey, MetalTile>()
        self.cache.totalCostLimit = maxCacheSizeInBytes
    }
    
    func setTileData(tile: MetalTile, forKey key: Tile) {
        let estimatedCost = estimateTileByteSize(tile)
        cache.setObject(tile, forKey: TileCacheKey(key), cost: estimatedCost)
    }
    
    func getTile(forKey key: Tile) -> MetalTile? {
        return cache.object(forKey: TileCacheKey(key))
    }

    func removeAll() {
        cache.removeAllObjects()
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
