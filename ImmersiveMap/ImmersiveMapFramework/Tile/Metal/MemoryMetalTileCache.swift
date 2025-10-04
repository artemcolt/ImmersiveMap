import Foundation

class MemoryMetalTileCache {
    private let cache: NSCache<NSString, MetalTile>
    
    init(maxCacheSizeInBytes: Int) {
        self.cache = NSCache<NSString, MetalTile>()
        self.cache.totalCostLimit = maxCacheSizeInBytes
    }
    
    func setTileData(tile: MetalTile, forKey key: String) {
        let estimatedCost = estimateTileByteSize(tile)
        cache.setObject(tile, forKey: key as NSString, cost: estimatedCost)
    }
    
    func getTile(forKey key: String) -> MetalTile? {
        return cache.object(forKey: key as NSString)
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
