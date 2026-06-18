// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class NightLightsAtlasTexture {
    private static let defaultPageSize = 4096
    private static let defaultTileSize = 1024
    private static let bytesPerPixel = 2

    private let device: MTLDevice
    private let pageSize: Int
    private let tileSize: Int
    private let slotsPerSide: Int
    private let slotsPerPage: Int

    private var pages: [MTLTexture] = []

    init(device: MTLDevice, pageSize: Int = 4096, tileSize: Int = 1024) {
        let geometry = Self.validatedGeometry(pageSize: pageSize, tileSize: tileSize)
        self.device = device
        self.pageSize = geometry.pageSize
        self.tileSize = geometry.tileSize
        self.slotsPerSide = geometry.pageSize / geometry.tileSize
        self.slotsPerPage = slotsPerSide * slotsPerSide
    }

    // Shaders must only sample slots described by `entries`; untouched slots are not part of the atlas contract.
    // Newly created pages are still cleared to keep readbacks and accidental unused-slot access deterministic.
    func update(tiles: [NightLightsTileData]) -> NightLightsAtlasState {
        guard !tiles.isEmpty else {
            removeAll()
            return .empty
        }

        var entries: [NightLightsAtlasEntry] = []
        entries.reserveCapacity(tiles.count)

        for tileData in tiles where isValid(tileData) {
            let slotIndex = entries.count
            let pageIndex = slotIndex / slotsPerPage
            let slotInPage = slotIndex % slotsPerPage
            let column = slotInPage % slotsPerSide
            let row = slotInPage / slotsPerSide

            guard let page = texturePage(at: pageIndex) else {
                continue
            }
            guard let tileBytesPerRow = Self.bytesPerRow(forSideLength: tileSize) else {
                continue
            }

            let originX = column * tileSize
            let originY = row * tileSize
            let region = MTLRegionMake2D(originX, originY, tileSize, tileSize)
            tileData.bytes.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }
                page.replace(region: region,
                             mipmapLevel: 0,
                             withBytes: baseAddress,
                             bytesPerRow: tileBytesPerRow)
            }

            let uvScale = SIMD2<Float>(Float(tileSize) / Float(pageSize),
                                       Float(tileSize) / Float(pageSize))
            let uvOrigin = SIMD2<Float>(Float(originX) / Float(pageSize),
                                        Float(originY) / Float(pageSize))
            entries.append(NightLightsAtlasEntry(tile: tileData.tile,
                                                 pageIndex: pageIndex,
                                                 uvOrigin: uvOrigin,
                                                 uvScale: uvScale))
        }

        if entries.isEmpty {
            removeAll()
            return .empty
        }

        let exposedPages = Array(pages.prefix(requiredPageCount(forEntryCount: entries.count)))
        if exposedPages.count < pages.count {
            pages = exposedPages
        }
        return NightLightsAtlasState(pages: exposedPages, entries: entries)
    }

    func removeAll() {
        pages.removeAll()
    }

    private func isValid(_ tileData: NightLightsTileData) -> Bool {
        guard let expectedByteCount = Self.textureByteCount(forSideLength: tileSize) else {
            return false
        }
        return tileData.width == tileSize &&
        tileData.height == tileSize &&
        tileData.bytes.count == expectedByteCount
    }

    private func texturePage(at index: Int) -> MTLTexture? {
        while pages.count <= index {
            guard let texture = makeTexturePage(index: pages.count) else {
                return nil
            }
            pages.append(texture)
        }
        return pages[index]
    }

    private func makeTexturePage(index: Int) -> MTLTexture? {
        guard let pageBytesPerRow = Self.bytesPerRow(forSideLength: pageSize),
              let clearByteCount = Self.textureByteCount(forSideLength: pageSize) else {
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm,
                                                                  width: pageSize,
                                                                  height: pageSize,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "NightLightsAtlasTexturePage\(index)"
        if let texture {
            clearTexture(texture, byteCount: clearByteCount, bytesPerRow: pageBytesPerRow)
        }
        return texture
    }

    private func clearTexture(_ texture: MTLTexture, byteCount: Int, bytesPerRow: Int) {
        let bytes = [UInt8](repeating: 0, count: byteCount)
        bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            texture.replace(region: MTLRegionMake2D(0, 0, pageSize, pageSize),
                            mipmapLevel: 0,
                            withBytes: baseAddress,
                            bytesPerRow: bytesPerRow)
        }
    }

    private func requiredPageCount(forEntryCount entryCount: Int) -> Int {
        guard entryCount > 0 else {
            return 0
        }
        return ((entryCount - 1) / slotsPerPage) + 1
    }

    private static func validatedGeometry(pageSize: Int, tileSize: Int) -> (pageSize: Int, tileSize: Int) {
        guard pageSize > 0,
              tileSize > 0,
              tileSize <= pageSize,
              pageSize % tileSize == 0,
              bytesPerRow(forSideLength: tileSize) != nil,
              bytesPerRow(forSideLength: pageSize) != nil,
              textureByteCount(forSideLength: tileSize) != nil,
              textureByteCount(forSideLength: pageSize) != nil else {
            return (defaultPageSize, defaultTileSize)
        }

        let slotsPerSide = pageSize / tileSize
        guard checkedProduct(slotsPerSide, slotsPerSide) != nil else {
            return (defaultPageSize, defaultTileSize)
        }
        return (pageSize, tileSize)
    }

    private static func bytesPerRow(forSideLength sideLength: Int) -> Int? {
        checkedProduct(sideLength, bytesPerPixel)
    }

    private static func textureByteCount(forSideLength sideLength: Int) -> Int? {
        guard let pixelCount = checkedProduct(sideLength, sideLength) else {
            return nil
        }
        return checkedProduct(pixelCount, bytesPerPixel)
    }

    private static func checkedProduct(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }
}
