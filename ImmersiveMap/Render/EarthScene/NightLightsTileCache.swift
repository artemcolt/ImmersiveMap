// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO

struct NightLightsTileData {
    let tile: Tile
    let width: Int
    let height: Int
    let bytes: [UInt8]
}

// Owned by the render preparation path; callers should keep access single-threaded.
final class NightLightsTileCache {
    private static let maxPixelCount = 4096 * 4096

    private let capacity: Int
    private let loader: (Tile) -> URL?

    private var cachedTiles: [Tile: NightLightsTileData] = [:]
    private var tileOrder: [Tile] = []

    init(capacity: Int = 128, loader: @escaping (Tile) -> URL?) {
        self.capacity = max(1, capacity)
        self.loader = loader
    }

    func tileData(for tile: Tile) -> NightLightsTileData? {
        if let cachedTile = cachedTiles[tile] {
            markRecentlyUsed(tile)
            return cachedTile
        }

        guard let url = loader(tile),
              let decodedTile = Self.decodeTile(tile, from: url) else {
            return nil
        }

        insert(decodedTile)
        return decodedTile
    }

    func removeAll() {
        cachedTiles.removeAll()
        tileOrder.removeAll()
    }

    private func insert(_ tileData: NightLightsTileData) {
        cachedTiles[tileData.tile] = tileData
        markRecentlyUsed(tileData.tile)

        while tileOrder.count > capacity, let leastRecentlyUsedTile = tileOrder.first {
            cachedTiles.removeValue(forKey: leastRecentlyUsedTile)
            tileOrder.removeFirst()
        }
    }

    private func markRecentlyUsed(_ tile: Tile) {
        tileOrder.removeAll { $0 == tile }
        tileOrder.append(tile)
    }

    private static func decodeTile(_ tile: Tile, from url: URL) -> NightLightsTileData? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = image.width
        let height = image.height
        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard width > 0,
              height > 0,
              !pixelCount.overflow,
              pixelCount.partialValue <= maxPixelCount else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: pixelCount.partialValue)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &bytes,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return NightLightsTileData(tile: tile, width: width, height: height, bytes: bytes)
    }
}
