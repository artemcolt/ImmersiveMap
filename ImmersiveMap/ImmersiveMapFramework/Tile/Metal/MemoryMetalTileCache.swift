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
    
    private func estimateTileByteSize(_ tile: MetalTile) -> Int {
        let tileBuffers = tile.tileBuffers
        
        // Estimate size based on buffer lengths
        let verticesSize = tileBuffers.verticesBuffer.allocatedSize
        let indicesSize = tileBuffers.indicesBuffer.allocatedSize
        let stylesSize = tileBuffers.stylesBuffer.allocatedSize
        return verticesSize + indicesSize + stylesSize
    }
}
