// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class NightLightsTileCacheTests: XCTestCase {
    func testLoadsSmallGrayscaleJPEGIntoBytesAndDimensions() throws {
        let tile = Tile(x: 1, y: 2, z: 3)
        let url = try makeJPEG(width: 2, height: 2, bytes: [0, 80, 160, 255])
        let cache = NightLightsTileCache { requestedTile in
            requestedTile == tile ? url : nil
        }

        let data = try XCTUnwrap(cache.tileData(for: tile))

        XCTAssertEqual(data.tile, tile)
        XCTAssertEqual(data.width, 2)
        XCTAssertEqual(data.height, 2)
        XCTAssertEqual(data.bytes.count, 4)
        XCTAssertGreaterThan(data.bytes.max() ?? 0, data.bytes.min() ?? 0)
    }

    func testMissingTileReturnsNil() {
        let cache = NightLightsTileCache { _ in nil }

        XCTAssertNil(cache.tileData(for: Tile(x: 1, y: 2, z: 3)))
    }

    func testLoadsPNGIntoRowMajorGrayscaleBytes() throws {
        let tile = Tile(x: 4, y: 5, z: 6)
        let url = try makePNG(width: 3,
                              height: 2,
                              bytes: [
                                  10, 60, 110,
                                  160, 210, 250
                              ])
        let cache = NightLightsTileCache { requestedTile in
            requestedTile == tile ? url : nil
        }

        let data = try XCTUnwrap(cache.tileData(for: tile))

        XCTAssertEqual(data.width, 3)
        XCTAssertEqual(data.height, 2)
        XCTAssertEqual(data.bytes, [
            10, 60, 110,
            160, 210, 250
        ])
    }

    func testCapacityEvictsLeastRecentlyUsedTile() throws {
        let tileA = Tile(x: 1, y: 2, z: 3)
        let tileB = Tile(x: 2, y: 2, z: 3)
        let urlA = try makeJPEG(width: 1, height: 1, bytes: [64])
        let urlB = try makeJPEG(width: 1, height: 1, bytes: [192])
        var loadCounts: [Tile: Int] = [:]
        let cache = NightLightsTileCache(capacity: 1) { tile in
            loadCounts[tile, default: 0] += 1
            return tile == tileA ? urlA : urlB
        }

        XCTAssertNotNil(cache.tileData(for: tileA))
        XCTAssertNotNil(cache.tileData(for: tileB))
        XCTAssertNotNil(cache.tileData(for: tileA))

        XCTAssertEqual(loadCounts[tileA], 2)
        XCTAssertEqual(loadCounts[tileB], 1)
    }

    func testCacheHitPromotesTileBeforeEvictingLeastRecentlyUsedTile() throws {
        let tileA = Tile(x: 1, y: 2, z: 3)
        let tileB = Tile(x: 2, y: 2, z: 3)
        let tileC = Tile(x: 3, y: 2, z: 3)
        let urls = [
            tileA: try makeJPEG(width: 1, height: 1, bytes: [64]),
            tileB: try makeJPEG(width: 1, height: 1, bytes: [128]),
            tileC: try makeJPEG(width: 1, height: 1, bytes: [192])
        ]
        var loadCounts: [Tile: Int] = [:]
        let cache = NightLightsTileCache(capacity: 2) { tile in
            loadCounts[tile, default: 0] += 1
            return urls[tile]
        }

        XCTAssertNotNil(cache.tileData(for: tileA))
        XCTAssertNotNil(cache.tileData(for: tileB))
        XCTAssertNotNil(cache.tileData(for: tileA))
        XCTAssertNotNil(cache.tileData(for: tileC))
        XCTAssertNotNil(cache.tileData(for: tileA))
        XCTAssertNotNil(cache.tileData(for: tileB))

        XCTAssertEqual(loadCounts[tileA], 1)
        XCTAssertEqual(loadCounts[tileB], 2)
        XCTAssertEqual(loadCounts[tileC], 1)
    }

    func testRemoveAllClearsCacheAndReloadsOnNextLookup() throws {
        let tile = Tile(x: 1, y: 2, z: 3)
        let url = try makeJPEG(width: 1, height: 1, bytes: [128])
        var loadCount = 0
        let cache = NightLightsTileCache { _ in
            loadCount += 1
            return url
        }

        XCTAssertNotNil(cache.tileData(for: tile))
        cache.removeAll()
        XCTAssertNotNil(cache.tileData(for: tile))

        XCTAssertEqual(loadCount, 2)
    }

    private func makeJPEG(width: Int, height: Int, bytes: [UInt8]) throws -> URL {
        XCTAssertEqual(bytes.count, width * height)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var mutableBytes = bytes
        guard let context = CGContext(data: &mutableBytes,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.jpeg.identifier as CFString,
                                                                1,
                                                                nil) else {
            throw XCTSkip("Could not create test JPEG")
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func makePNG(width: Int, height: Int, bytes: [UInt8]) throws -> URL {
        XCTAssertEqual(bytes.count, width * height)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var mutableBytes = bytes
        guard let context = CGContext(data: &mutableBytes,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.png.identifier as CFString,
                                                                1,
                                                                nil) else {
            throw XCTSkip("Could not create test PNG")
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
