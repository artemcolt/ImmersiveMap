import Foundation

struct PreparedTileCacheIdentity {
    let preparedFormatVersion: UInt32
    let styleRevision: UInt32
    let flatSeparateRoadRenderingMinimumZoom: UInt32
    let textRevision: UInt32
    let labelLanguage: MapSettings.LabelLanguage
    let houseNumbersEnabled: Bool
    let houseNumbersMinimumZoom: UInt32
    let capitalMaximumZoom: UInt32
    let cityMaximumZoom: UInt32
    let smallSettlementMaximumZoom: UInt32
    let landmarkMinimumZoom: UInt32
    let addTestBorders: Bool

    var namespaceComponent: String {
        "s\(styleRevision)-r\(flatSeparateRoadRenderingMinimumZoom)-t\(textRevision)-l\(labelLanguage.preparedTileCacheNamespaceKey)-h\(houseNumbersEnabled ? 1 : 0)-z\(houseNumbersMinimumZoom)-c\(capitalMaximumZoom)-y\(cityMaximumZoom)-m\(smallSettlementMaximumZoom)-k\(landmarkMinimumZoom)-b\(addTestBorders ? 1 : 0)"
    }
}

private extension MapSettings.LabelLanguage {
    var preparedTileCacheNamespaceKey: String {
        switch self {
        case .english:
            return "en"
        case .russian:
            return "ru"
        }
    }
}

final class PreparedTileDiskCaching {
    static let preparedFormatVersion: UInt32 = 13

    private let cacheRootDirectory: URL
    private let cacheDirectory: URL
    private let cacheDuration: TimeInterval
    private let cacheIdentity: PreparedTileCacheIdentity
    private let fileManager: FileManager

    init(config: MapSettings,
         cacheIdentity: PreparedTileCacheIdentity,
         fileManager: FileManager = .default,
         baseCachesDirectory: URL? = nil) {
        self.cacheDuration = config.tiles.cache.preparedDiskTimeToLive
        self.cacheIdentity = cacheIdentity
        self.fileManager = fileManager

        let cachesDirectory = baseCachesDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheRootDirectory = cachesDirectory.appendingPathComponent("MapPreparedTiles")
        self.cacheDirectory = cacheRootDirectory
            .appendingPathComponent("v\(cacheIdentity.preparedFormatVersion)")
            .appendingPathComponent(cacheIdentity.namespaceComponent)

        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("Failed to create prepared tile cache directory: \(error)")
            #endif
        }

        if config.tiles.cache.clearDiskCachesOnLaunch {
            do {
                try clearAllCache()
            } catch {
                #if DEBUG
                print("Failed to clear prepared tile cache: \(error)")
                #endif
            }
        }
    }

    func requestPreparedDiskCached(tile: Tile) async -> PreparedTileCPU? {
        let cachePath = cachePathFor(tile: tile)
        guard let data = loadCachedFile(at: cachePath) else {
            return nil
        }

        do {
            return try PreparedTileDiskCodec.decode(data: data,
                                                    expectedTile: tile,
                                                    cacheIdentity: cacheIdentity)
        } catch {
            removeFromDisk(tile: tile)
            return nil
        }
    }

    func saveOnDisk(tile: Tile, preparedTile: PreparedTileCPU) {
        guard preparedTile.tile == tile else {
            return
        }
        let cachePath = cachePathFor(tile: tile)
        do {
            let data = try PreparedTileDiskCodec.encode(preparedTile: preparedTile,
                                                        cacheIdentity: cacheIdentity)
            try saveToCache(data: data, for: cachePath)
        } catch {
            #if DEBUG
            print("Failed to save prepared tile to \(cachePath.path): \(error)")
            #endif
        }
    }

    func removeFromDisk(tile: Tile) {
        let cachePath = cachePathFor(tile: tile)
        do {
            try fileManager.removeItem(at: cachePath)
        } catch {
            // Best-effort removal for corrupted or obsolete prepared entries.
        }
    }

    func clearAllCache() throws {
        if fileManager.fileExists(atPath: cacheRootDirectory.path) {
            try fileManager.removeItem(at: cacheRootDirectory)
        }
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachePathFor(tile: Tile) -> URL {
        let fileName = "\(tile.z)_\(tile.x)_\(tile.y).ptile"
        return cacheDirectory.appendingPathComponent(fileName)
    }

    private func saveToCache(data: Data, for cachePath: URL) throws {
        let directory = cachePath.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: cachePath, options: .atomic)
    }

    private func loadCachedFile(at cachePath: URL) -> Data? {
        guard fileManager.fileExists(atPath: cachePath.path) else {
            return nil
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: cachePath.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            removeFileBestEffort(at: cachePath)
            return nil
        }

        if Date().timeIntervalSince(modificationDate) > cacheDuration {
            removeFileBestEffort(at: cachePath)
            return nil
        }

        do {
            return try Data(contentsOf: cachePath)
        } catch {
            removeFileBestEffort(at: cachePath)
            return nil
        }
    }

    private func removeFileBestEffort(at url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
