// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import Metal
import XCTest

final class NightLightsAtlasTextureTests: XCTestCase {
    func testSingleTileBuildsAtlasMetadata() throws {
        let atlas = try makeAtlas(pageSize: 2048, tileSize: 1024)
        let state = atlas.update(tiles: [makeTileData(tile: Tile(x: 1, y: 2, z: 3))])

        XCTAssertEqual(state.pages.count, 1)
        XCTAssertEqual(state.entries, [
            NightLightsAtlasEntry(tile: Tile(x: 1, y: 2, z: 3),
                                  pageIndex: 0,
                                  uvOrigin: SIMD2<Float>(0.0, 0.0),
                                  uvScale: SIMD2<Float>(0.5, 0.5))
        ])
    }

    func testMultipleTilesPackRowMajorAcrossPages() throws {
        let atlas = try makeAtlas(pageSize: 2048, tileSize: 1024)
        let tiles = (0..<5).map { makeTileData(tile: Tile(x: $0, y: 0, z: 4)) }

        let state = atlas.update(tiles: tiles)

        XCTAssertEqual(state.pages.count, 2)
        XCTAssertEqual(state.entries.map(\.pageIndex), [0, 0, 0, 0, 1])
        XCTAssertEqual(state.entries.map(\.uvOrigin), [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.5, 0.0),
            SIMD2<Float>(0.0, 0.5),
            SIMD2<Float>(0.5, 0.5),
            SIMD2<Float>(0.0, 0.0)
        ])
        XCTAssertEqual(state.entries.map(\.uvScale), Array(repeating: SIMD2<Float>(0.5, 0.5), count: 5))
    }

    func testInvalidTilesAreSkipped() throws {
        let atlas = try makeAtlas(pageSize: 2048, tileSize: 1024)
        let validTile = makeTileData(tile: Tile(x: 1, y: 0, z: 4))
        let wrongWidth = NightLightsTileData(tile: Tile(x: 2, y: 0, z: 4),
                                            width: 512,
                                            height: 1024,
                                            bytes: [UInt8](repeating: 1, count: 512 * 1024))
        let wrongByteCount = NightLightsTileData(tile: Tile(x: 3, y: 0, z: 4),
                                                width: 1024,
                                                height: 1024,
                                                bytes: [UInt8](repeating: 1, count: 1024))

        let state = atlas.update(tiles: [wrongWidth, validTile, wrongByteCount])

        XCTAssertEqual(state.pages.count, 1)
        XCTAssertEqual(state.entries.map(\.tile), [validTile.tile])
        XCTAssertEqual(state.entries.first?.uvOrigin, SIMD2<Float>(0.0, 0.0))
    }

    func testEmptyUpdateReturnsEmptyAfterPreviousNonEmptyUpdate() throws {
        let atlas = try makeAtlas(pageSize: 2048, tileSize: 1024)
        _ = atlas.update(tiles: [makeTileData(tile: Tile(x: 1, y: 0, z: 4))])

        let state = atlas.update(tiles: [])

        XCTAssertTrue(state.pages.isEmpty)
        XCTAssertTrue(state.entries.isEmpty)
    }

    func testNightLightsAtlasEntryUniformLayoutMatchesMetal() {
        XCTAssertEqual(MemoryLayout<NightLightsAtlasEntryUniform>.stride, 32)
        XCTAssertEqual(MemoryLayout<NightLightsAtlasEntryUniform>.alignment, 16)
        XCTAssertEqual(MemoryLayout<NightLightsAtlasEntryUniform>.offset(of: \.tileAndPage), 0)
        XCTAssertEqual(MemoryLayout<NightLightsAtlasEntryUniform>.offset(of: \.uvOriginAndScale), 16)
    }

    func testNightLightsAtlasEntryUniformAccessorsMapPackedFields() {
        let uniform = NightLightsAtlasEntryUniform(tile: SIMD3<Int32>(1, 2, 3),
                                                   pageIndex: 4,
                                                   uvOrigin: SIMD2<Float>(0.25, 0.5),
                                                   uvScale: SIMD2<Float>(0.125, 0.25))

        XCTAssertEqual(uniform.tileAndPage, SIMD4<Int32>(1, 2, 3, 4))
        XCTAssertEqual(uniform.uvOriginAndScale, SIMD4<Float>(0.25, 0.5, 0.125, 0.25))
        XCTAssertEqual(uniform.tile, SIMD3<Int32>(1, 2, 3))
        XCTAssertEqual(uniform.pageIndex, 4)
        XCTAssertEqual(uniform.uvOrigin, SIMD2<Float>(0.25, 0.5))
        XCTAssertEqual(uniform.uvScale, SIMD2<Float>(0.125, 0.25))
    }

    func testNightLightsAtlasSurfaceBindingCapsPagesAndEntries() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is unavailable")
        }
        let pages = (0..<(NightLightsAtlasSurfaceBinding.maxPageCount + 2)).compactMap { index in
            makeTexture(device: device, label: "NightLightsTestPage\(index)")
        }
        let invalidEntry = NightLightsAtlasEntry(tile: Tile(x: 999, y: 999, z: 6),
                                                 pageIndex: NightLightsAtlasSurfaceBinding.maxPageCount + 1,
                                                 uvOrigin: SIMD2<Float>(0, 0),
                                                 uvScale: SIMD2<Float>(0.25, 0.25))
        let entries = [invalidEntry] + (0..<(NightLightsAtlasSurfaceBinding.maxEntryCount + 2)).map { index in
            NightLightsAtlasEntry(tile: Tile(x: index, y: index + 1, z: 6),
                                  pageIndex: index % NightLightsAtlasSurfaceBinding.maxPageCount,
                                  uvOrigin: SIMD2<Float>(Float(index), Float(index + 1)),
                                  uvScale: SIMD2<Float>(0.25, 0.25))
        }

        let binding = NightLightsAtlasSurfaceBinding(state: NightLightsAtlasState(pages: pages,
                                                                                  entries: entries))

        XCTAssertEqual(binding.pages.count, NightLightsAtlasSurfaceBinding.maxPageCount)
        XCTAssertEqual(binding.entryUniforms.count, NightLightsAtlasSurfaceBinding.maxEntryCount)
        XCTAssertEqual(binding.entryUniforms.first?.tileAndPage, SIMD4<Int32>(0, 1, 6, 0))
        XCTAssertEqual(binding.entryUniforms.last?.tile.x, Int32(NightLightsAtlasSurfaceBinding.maxEntryCount - 1))
        XCTAssertFalse(binding.entryUniforms.contains { $0.tile.x == 999 })
    }

    func testNightLightsAtlasSurfaceBindingShaderBudgetContract() {
        XCTAssertEqual(NightLightsAtlasSurfaceBinding.maxPageCount, 8)
        XCTAssertEqual(NightLightsAtlasSurfaceBinding.maxEntryCount, 128)
        XCTAssertLessThanOrEqual(NightLightsAtlasSurfaceBinding.maxEntryCount *
                                 MemoryLayout<NightLightsAtlasEntryUniform>.stride,
                                 4096)
    }

    func testInvalidInitializerParametersFallBackToDefaultAtlasGeometry() throws {
        let invalidInputs = [
            (pageSize: 0, tileSize: 1024),
            (pageSize: 4096, tileSize: 0),
            (pageSize: 512, tileSize: 1024),
            (pageSize: 3000, tileSize: 1024)
        ]

        for input in invalidInputs {
            let atlas = try makeAtlas(pageSize: input.pageSize, tileSize: input.tileSize)

            let state = atlas.update(tiles: [makeTileData(tile: Tile(x: 1, y: 0, z: 4))])

            XCTAssertEqual(state.pages.count, 1)
            XCTAssertEqual(state.entries.first?.uvOrigin, SIMD2<Float>(0.0, 0.0))
            XCTAssertEqual(state.entries.first?.uvScale, SIMD2<Float>(0.25, 0.25))
        }
    }

    func testUploadsTilesRowMajorAndClearsUntouchedSlots() throws {
        let atlas = try makeAtlas(pageSize: 4, tileSize: 2)
        let tiles = [
            makeTileData(tile: Tile(x: 0, y: 0, z: 1), width: 2, height: 2, bytes: [1, 2, 3, 4]),
            makeTileData(tile: Tile(x: 1, y: 0, z: 1), width: 2, height: 2, bytes: [5, 6, 7, 8]),
            makeTileData(tile: Tile(x: 0, y: 1, z: 1), width: 2, height: 2, bytes: [9, 10, 11, 12])
        ]

        let state = atlas.update(tiles: tiles)

        let page = try XCTUnwrap(state.pages.first)
        var bytes = [UInt8](repeating: 255, count: 4 * 4)
        page.getBytes(&bytes,
                      bytesPerRow: 4,
                      from: MTLRegionMake2D(0, 0, 4, 4),
                      mipmapLevel: 0)
        XCTAssertEqual(bytes, [
            1, 2, 5, 6,
            3, 4, 7, 8,
            9, 10, 0, 0,
            11, 12, 0, 0
        ])
    }

    private func makeAtlas(pageSize: Int, tileSize: Int) throws -> NightLightsAtlasTexture {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is unavailable")
        }
        return NightLightsAtlasTexture(device: device, pageSize: pageSize, tileSize: tileSize)
    }

    private func makeTexture(device: MTLDevice, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                                                                  width: 4,
                                                                  height: 4,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    private func makeTileData(tile: Tile) -> NightLightsTileData {
        makeTileData(tile: tile,
                     width: 1024,
                     height: 1024,
                     bytes: [UInt8](repeating: UInt8(tile.x), count: 1024 * 1024))
    }

    private func makeTileData(tile: Tile, width: Int, height: Int, bytes: [UInt8]) -> NightLightsTileData {
        NightLightsTileData(tile: tile,
                            width: width,
                            height: height,
                            bytes: bytes)
    }
}
