// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct NightLightsTileMapping: Equatable {
    let tile: Tile
    let uvOrigin: SIMD2<Float>
    let uvScale: SIMD2<Float>
}

final class NightLightsTileSet {
    private static let metadataResourceName = "night_lights_tiles_metadata"

    struct Metadata: Codable, Equatable {
        let version: Int
        let format: String
        let tileSize: Int
        let minZoom: Int
        let maxZoom: Int
        let source: String
        let attribution: String
    }

    let metadata: Metadata

    private let bundle: Bundle

    init(metadata: Metadata, bundle: Bundle = .module) {
        self.metadata = metadata
        self.bundle = bundle
    }

    convenience init(bundle: Bundle = .module) throws {
        let metadataURL = try Self.metadataURL(in: bundle)
        let data = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        self.init(metadata: metadata, bundle: bundle)
    }

    func bestAvailableTile(for tile: Tile) -> Tile {
        if tile.z < metadata.minZoom {
            let zoomDifference = metadata.minZoom - tile.z
            return Tile(x: tile.x << zoomDifference,
                        y: tile.y << zoomDifference,
                        z: metadata.minZoom)
        }

        if tile.z > metadata.maxZoom, let parent = tile.findParentTile(atZoom: metadata.maxZoom) {
            return parent
        }

        return tile
    }

    func mapping(for tile: Tile) -> NightLightsTileMapping? {
        guard tile.z >= metadata.minZoom else {
            return nil
        }

        let sourceTile = bestAvailableTile(for: tile)
        guard tile.z > sourceTile.z else {
            return NightLightsTileMapping(tile: sourceTile,
                                          uvOrigin: SIMD2<Float>(0.0, 0.0),
                                          uvScale: SIMD2<Float>(1.0, 1.0))
        }

        let scale = 1 << (tile.z - sourceTile.z)
        let uvScale = 1.0 / Float(scale)
        let originX = Float(tile.x - sourceTile.x * scale) * uvScale
        let originY = Float(tile.y - sourceTile.y * scale) * uvScale

        return NightLightsTileMapping(tile: sourceTile,
                                      uvOrigin: SIMD2(originX, originY),
                                      uvScale: SIMD2(uvScale, uvScale))
    }

    func url(for tile: Tile) -> URL? {
        let sourceTile = bestAvailableTile(for: tile)
        let resourceName = String(sourceTile.y)
        let flatResourceName = "night_lights_\(sourceTile.z)_\(sourceTile.x)_\(sourceTile.y)"
        let subdirectory = "NightLightsTiles/\(sourceTile.z)/\(sourceTile.x)"
        let processedSubdirectory = "Render/EarthScene/Resources/\(subdirectory)"
        let flatURL = bundle.bundleURL.appendingPathComponent("\(flatResourceName).\(metadata.format)")

        if FileManager.default.fileExists(atPath: flatURL.path) {
            return flatURL
        }

        return bundle.url(forResource: flatResourceName, withExtension: metadata.format)
            ?? bundle.url(forResource: resourceName,
                          withExtension: metadata.format,
                          subdirectory: subdirectory)
            ?? bundle.url(forResource: resourceName,
                          withExtension: metadata.format,
                          subdirectory: processedSubdirectory)
    }

    private static func metadataURL(in bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: metadataResourceName, withExtension: "json") {
            return url
        }

        if let url = bundle.url(forResource: metadataResourceName,
                                withExtension: "json",
                                subdirectory: "NightLightsTiles") {
            return url
        }

        if let url = bundle.url(forResource: metadataResourceName,
                                withExtension: "json",
                                subdirectory: "Render/EarthScene/Resources/NightLightsTiles") {
            return url
        }

        if let url = bundle.url(forResource: "metadata",
                                withExtension: "json",
                                subdirectory: "NightLightsTiles") {
            return url
        }

        if let url = bundle.url(forResource: "metadata",
                                withExtension: "json",
                                subdirectory: "Render/EarthScene/Resources/NightLightsTiles") {
            return url
        }

        throw LoadError.missingMetadata
    }

    private enum LoadError: Error, CustomStringConvertible {
        case missingMetadata

        var description: String {
            switch self {
            case .missingMetadata:
                return "missing bundled night_lights_tiles_metadata.json"
            }
        }
    }
}
