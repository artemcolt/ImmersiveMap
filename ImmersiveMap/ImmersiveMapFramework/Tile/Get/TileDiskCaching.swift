//
//  DiscCached.swift
//  TucikMap
//
//  Created by Artem on 6/6/25.
//

import Foundation

class TileDiskCaching {
    private let cacheDirectory: URL
    private let cacheDuration: TimeInterval = 7 * 24 * 60 * 60 // 1 week in seconds
    private let config: MapConfiguration
    
    init(config: MapConfiguration) {
        self.config = config
        // Initialize cache directory
        let fileManager = FileManager.default
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDirectory.appendingPathComponent("MapTiles")
        
        // Create cache directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create cache directory: \(error)")
        }
        
        let clearDownloadedOnDiskTiles = config.clearDownloadedOnDiskTiles
        if clearDownloadedOnDiskTiles {
            do {
                try clearAllCache()
            } catch {
                print("Failed to clear cache: \(error)")
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
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
            print("MapTiles cache directory removed successfully.")
        } else {
            print("MapTiles cache directory does not exist.")
        }
        // Recreate the cache directory after clearing
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            print("MapTiles cache directory recreated successfully.")
        } catch {
            print("Failed to recreate cache directory: \(error)")
            throw error
        }
    }
    
    func saveOnDisk(tile: Tile, data: Data) {
        let pathFor = cachePathFor(zoom: tile.z, x: tile.x, y: tile.y)
        saveToCache(data: data, for: pathFor)
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
            print("Failed to create cache directory \(directory.path): \(error)")
            return
        }
        
        do {
            // Save tile data
            try data.write(to: cachePath, options: .atomic)
            //print("Saved tile to: \(cachePath.path)")
        } catch {
            print("Failed to save tile to \(cachePath.path): \(error)")
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
            print("Failed to read attributes for tile at: \(cachePath.path)")
            return nil
        }
        
        let currentDate = Date()
        if currentDate.timeIntervalSince(modificationDate) > cacheDuration {
            // Tile is outdated, remove it
            try? fileManager.removeItem(at: cachePath)
            print("Removed outdated tile at: \(cachePath.path)")
            return nil
        }
        
        // Load tile data
        do {
            let data = try Data(contentsOf: cachePath)
            //print("Loaded cached tile from: \(cachePath.path)")
            return data
        } catch {
            print("Failed to load tile data from \(cachePath.path): \(error)")
            return nil
        }
    }
}
