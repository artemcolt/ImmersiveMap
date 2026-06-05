// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

class TileDiskCaching {
    private let cacheRootDirectory: URL
    private let cacheDirectory: URL
    private let cacheDuration: TimeInterval
    
    init(config: ImmersiveMapSettings) {
        self.cacheDuration = config.tiles.cache.rawDiskTimeToLive
        // Initialize cache directory
        let fileManager = FileManager.default
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheRootDirectory = cachesDirectory.appendingPathComponent("MapTiles")
        self.cacheDirectory = cacheRootDirectory.appendingPathComponent(Self.cacheNamespace(for: config.tiles.network))
        
        // Create cache directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("Failed to create cache directory: \(error)")
            #endif
        }
        
        let clearDownloadedOnDiskTiles = config.tiles.cache.clearDiskCachesOnLaunch
        if clearDownloadedOnDiskTiles {
            do {
                try clearAllCache()
            } catch {
                #if DEBUG
                print("Failed to clear cache: \(error)")
                #endif
            }
        }
    }
    
    func requestDiskCached(tile: Tile) async -> Data? {
        let zoom = tile.z
        let x = tile.x
        let y = tile.y
        let cachePath = cachePathFor(zoom: zoom, x: x, y: y)
        let data = loadCachedTile(at: cachePath)
        //if (data != nil) { print("Get from disk cache \(tile)") }
        return data
    }
    
    func clearAllCache() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheRootDirectory.path) {
            try fileManager.removeItem(at: cacheRootDirectory)
            #if DEBUG
            print("MapTiles cache directory removed successfully.")
            #endif
        } else {
            #if DEBUG
            print("MapTiles cache directory does not exist.")
            #endif
        }
        // Recreate the cache directory after clearing
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            #if DEBUG
            print("MapTiles cache directory recreated successfully.")
            #endif
        } catch {
            #if DEBUG
            print("Failed to recreate cache directory: \(error)")
            #endif
            throw error
        }
    }
    
    func saveOnDisk(tile: Tile, data: Data) {
        let pathFor = cachePathFor(zoom: tile.z, x: tile.x, y: tile.y)
        saveToCache(data: data, for: pathFor)
    }

    func removeFromDisk(tile: Tile) {
        let pathFor = cachePathFor(zoom: tile.z, x: tile.x, y: tile.y)
        do {
            try FileManager.default.removeItem(at: pathFor)
        } catch {
            // Ignore if file does not exist; removal is best-effort for corrupted cache entries.
        }
    }

    private static func cacheNamespace(for network: ImmersiveMapSettings.TileSettings.NetworkSettings) -> String {
        var hash: UInt64 = 1469598103934665603
        mix(network.tileBaseURL.absoluteString, into: &hash)
        switch network.authorizationMode {
        case .bearerHeader:
            mix("bearerHeader", into: &hash)
        case .accessTokenQuery(let parameterName):
            mix("accessTokenQuery:\(parameterName)", into: &hash)
        }
        return "v2-\(String(hash, radix: 16))"
    }

    private static func mix(_ string: String, into hash: inout UInt64) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
    }
    
    private func cachePathFor(zoom: Int, x: Int, y: Int) -> URL {
        let fileName = "\(zoom)_\(x)_\(y).mvt"
        return cacheDirectory.appendingPathComponent(fileName)
    }
    
    private func saveToCache(data: Data, for cachePath: URL) {
        let fileManager = FileManager.default
        let directory = cachePath.deletingLastPathComponent()
        
        // Ensure the cache directory exists
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("Failed to create cache directory \(directory.path): \(error)")
            #endif
            return
        }
        
        do {
            // Save tile data
            try data.write(to: cachePath, options: .atomic)
            //print("Saved tile to: \(cachePath.path)")
        } catch {
            #if DEBUG
            print("Failed to save tile to \(cachePath.path): \(error)")
            #endif
        }
    }
    
    private func loadCachedTile(at cachePath: URL) -> Data? {
        let fileManager = FileManager.default
        
        // Check if tile exists
        guard fileManager.fileExists(atPath: cachePath.path) else {
            //print("Tile not found at: \(cachePath.path)")
            return nil
        }
        
        // Check tile age using modification date
        guard let attributes = try? fileManager.attributesOfItem(atPath: cachePath.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            #if DEBUG
            print("Failed to read attributes for tile at: \(cachePath.path)")
            #endif
            return nil
        }
        
        let currentDate = Date()
        if currentDate.timeIntervalSince(modificationDate) > cacheDuration {
            // Tile is outdated, remove it
            try? fileManager.removeItem(at: cachePath)
            #if DEBUG
            print("Removed outdated tile at: \(cachePath.path)")
            #endif
            return nil
        }
        
        // Load tile data
        do {
            let data = try Data(contentsOf: cachePath)
            //print("Loaded cached tile from: \(cachePath.path)")
            return data
        } catch {
            #if DEBUG
            print("Failed to load tile data from \(cachePath.path): \(error)")
            #endif
            return nil
        }
    }
}
