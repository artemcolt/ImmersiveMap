//
//  LabelCache.swift
//  ImmersiveMap
//
//  Created by Artem on 1/3/26.
//

import Foundation
import Metal

final class LabelCache {
    private let metalDevice: MTLDevice
    private let computeGlobeToScreen: ComputeGlobeToScreen
    private var labelInputs: [GlobeLabelInput] = []
    private(set) var drawLabels: [DrawLabels] = []
    private let labelHoldSeconds: TimeInterval = 3.0
    private var labelTiles: [Tile: CachedTileLabels] = [:]
    private(set) var labelDuplicateBuffer: MTLBuffer
    private(set) var labelTilesList: [Tile] = []
    private(set) var labelTileIndices: [UInt32] = []
    private(set) var labelTileIndicesBuffer: MTLBuffer

    init(metalDevice: MTLDevice, computeGlobeToScreen: ComputeGlobeToScreen) {
        self.metalDevice = metalDevice
        self.computeGlobeToScreen = computeGlobeToScreen
        self.labelDuplicateBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt8>.stride,
            options: [.storageModeShared]
        )!
        self.labelTileIndicesBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: [.storageModeShared]
        )!
    }

    func update(visibleTiles: [PlaceTile], now: TimeInterval) {
        var labelsNeedsRebuild = updateLabelCache(visibleTiles: visibleTiles, now: now)
        labelsNeedsRebuild = expireLabelCache(now: now) || labelsNeedsRebuild
        if labelsNeedsRebuild {
            rebuildLabelBuffers(visibleTiles: visibleTiles)
        }
    }

    private func updateLabelCache(visibleTiles: [PlaceTile], now: TimeInterval) -> Bool {
        var changed = false
        for placeTile in visibleTiles {
            let tile = placeTile.metalTile.tile
            let tileKey = tile
            let tileBuffers = placeTile.metalTile.tileBuffers

            // тайл уже в кэше
            if var cached = labelTiles[tileKey] {
                cached.lastSeen = now
                labelTiles[tileKey] = cached
                continue
            }

            // в тайле нету лэйблов
            let labelsCount = tileBuffers.labelsCount
            if labelsCount == 0 {
                continue
            }

            let meta = tileBuffers.labelsMeta
            labelTiles[tileKey] = CachedTileLabels(
                tileKey: tileKey,
                lastSeen: now,
                labelsInputs: tileBuffers.labelsInputs,
                labelsMeta: meta,
                labelsVerticesBuffer: tileBuffers.labelsVerticesBuffer,
                labelsCount: labelsCount,
                labelsVerticesCount: tileBuffers.labelsVerticesCount
            )
            changed = true
        }

        return changed
    }

    private func expireLabelCache(now: TimeInterval) -> Bool {
        var expired: [Tile] = []
        for (tileKey, cached) in labelTiles {
            if now - cached.lastSeen > labelHoldSeconds {
                expired.append(tileKey)
            }
        }

        if expired.isEmpty {
            return false
        }

        for tileKey in expired {
            labelTiles.removeValue(forKey: tileKey)
        }

        return true
    }

    private func rebuildLabelBuffers(visibleTiles: [PlaceTile]) {
        labelInputs.removeAll(keepingCapacity: true)
        drawLabels.removeAll(keepingCapacity: true)
        labelTilesList.removeAll(keepingCapacity: true)
        labelTileIndices.removeAll(keepingCapacity: true)
        labelInputs.reserveCapacity(labelTiles.count * 8)
        var duplicateFlags: [UInt8] = []
        duplicateFlags.reserveCapacity(labelTiles.count * 8)
        var seenLabelKeys: Set<UInt64> = []
        labelTilesList.reserveCapacity(labelTiles.count)
        labelTileIndices.reserveCapacity(labelTiles.count * 8)

        var visibleKeys: [Tile] = []
        visibleKeys.reserveCapacity(visibleTiles.count)
        for placeTile in visibleTiles {
            visibleKeys.append(placeTile.metalTile.tile)
        }

        let visibleSet = Set(visibleKeys)
        var seenKeys: Set<Tile> = []
        for tileKey in visibleKeys {
            if seenKeys.contains(tileKey) {
                continue
            }
            seenKeys.insert(tileKey)
            guard let cached = labelTiles[tileKey] else {
                continue
            }
            let tileIndex = appendTileLabels(cached: cached)
            for meta in cached.labelsMeta {
                if seenLabelKeys.contains(meta.key) {
                    duplicateFlags.append(1)
                } else {
                    duplicateFlags.append(0)
                    seenLabelKeys.insert(meta.key)
                }
            }
            drawLabels.append(DrawLabels(
                labelsVerticesBuffer: cached.labelsVerticesBuffer,
                labelsCount: cached.labelsCount,
                labelsVerticesCount: cached.labelsVerticesCount
            ))
        }

        let retainedTiles = labelTiles.values.filter { visibleSet.contains($0.tileKey) == false }
        let sortedRetained = retainedTiles.sorted { $0.lastSeen > $1.lastSeen }
        for cached in sortedRetained {
            _ = appendTileLabels(cached: cached)
            for meta in cached.labelsMeta {
                if seenLabelKeys.contains(meta.key) {
                    duplicateFlags.append(1)
                } else {
                    duplicateFlags.append(0)
                    seenLabelKeys.insert(meta.key)
                }
            }
            drawLabels.append(DrawLabels(
                labelsVerticesBuffer: cached.labelsVerticesBuffer,
                labelsCount: cached.labelsCount,
                labelsVerticesCount: cached.labelsVerticesCount
            ))
        }

        computeGlobeToScreen.copyDataToBuffer(inputs: labelInputs)

        let duplicateNeeded = max(1, duplicateFlags.count) * MemoryLayout<UInt8>.stride
        if labelDuplicateBuffer.length < duplicateNeeded {
            labelDuplicateBuffer = metalDevice.makeBuffer(
                length: duplicateNeeded,
                options: [.storageModeShared]
            )!
        }
        if duplicateFlags.isEmpty == false {
            let bytesCount = duplicateFlags.count * MemoryLayout<UInt8>.stride
            duplicateFlags.withUnsafeBytes { bytes in
                labelDuplicateBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
            }
        }

        let indicesNeeded = max(1, labelTileIndices.count) * MemoryLayout<UInt32>.stride
        if labelTileIndicesBuffer.length < indicesNeeded {
            labelTileIndicesBuffer = metalDevice.makeBuffer(
                length: indicesNeeded,
                options: [.storageModeShared]
            )!
        }
        if labelTileIndices.isEmpty == false {
            let bytesCount = labelTileIndices.count * MemoryLayout<UInt32>.stride
            labelTileIndices.withUnsafeBytes { bytes in
                labelTileIndicesBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
            }
        }
    }

    private func appendTileLabels(cached: CachedTileLabels) -> UInt32 {
        let tileIndex = UInt32(labelTilesList.count)
        labelTilesList.append(cached.tileKey)
        labelInputs.append(contentsOf: cached.labelsInputs)
        let count = cached.labelsInputs.count
        if count > 0 {
            labelTileIndices.append(contentsOf: repeatElement(tileIndex, count: count))
        }
        return tileIndex
    }
}

private struct CachedTileLabels {
    let tileKey: Tile
    var lastSeen: TimeInterval
    let labelsInputs: [GlobeLabelInput]
    let labelsMeta: [GlobeLabelMeta]
    let labelsVerticesBuffer: MTLBuffer?
    let labelsCount: Int
    let labelsVerticesCount: Int
}
