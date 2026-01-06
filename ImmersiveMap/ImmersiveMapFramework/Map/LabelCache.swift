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
    private let labelScreenCompute: LabelScreenCompute
    private var labelInputs: [GlobeLabelInput] = []
    private(set) var drawLabels: [DrawLabels] = []
    private let labelHoldSeconds: TimeInterval = 3.0
    private var labelTiles: [Tile: CachedTileLabels] = [:]
    private var lastVisibleTileKeys: Set<Tile> = []
    private(set) var labelDuplicateBuffer: MTLBuffer
    private(set) var labelStateBuffer: MTLBuffer
    private(set) var labelInputsCount: Int = 0
    private(set) var labelTilesList: [Tile] = []
    private var labelStateIndices: [LabelStateIndex] = []
    private(set) var labelDesiredVisibilityBuffer: MTLBuffer
    private(set) var labelTileIndices: [UInt32] = []
    private(set) var labelTileIndicesBuffer: MTLBuffer

    init(metalDevice: MTLDevice, computeGlobeToScreen: LabelScreenCompute) {
        self.metalDevice = metalDevice
        self.labelScreenCompute = computeGlobeToScreen
        self.labelDuplicateBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt8>.stride,
            options: [.storageModeShared]
        )!
        self.labelStateBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<LabelState>.stride,
            options: [.storageModeShared]
        )!
        self.labelDesiredVisibilityBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt8>.stride,
            options: [.storageModeShared]
        )!
        self.labelTileIndicesBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: [.storageModeShared]
        )!
    }

    func update(visibleTiles: [PlaceTile], now: TimeInterval) {
        let currentVisibleKeys = Set(visibleTiles.map { $0.metalTile.tile })
        var labelsNeedsRebuild = updateLabelCache(visibleTiles: visibleTiles, now: now)
        labelsNeedsRebuild = expireLabelCache(now: now) || labelsNeedsRebuild
        if currentVisibleKeys != lastVisibleTileKeys {
            labelsNeedsRebuild = true
            lastVisibleTileKeys = currentVisibleKeys
        }
        if labelsNeedsRebuild {
            rebuildLabelBuffers(visibleTiles: visibleTiles, now: now)
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
            let labelsStates = Array(repeating: LabelState(alpha: 0, target: 0, changeTime: Float(now), alphaStart: 0),
                                     count: labelsCount)
            labelTiles[tileKey] = CachedTileLabels(
                tileKey: tileKey,
                lastSeen: now,
                labelsInputs: tileBuffers.labelsInputs,
                labelsMeta: meta,
                labelsVerticesBuffer: tileBuffers.labelsVerticesBuffer,
                labelsCount: labelsCount,
                labelsVerticesCount: tileBuffers.labelsVerticesCount,
                labelsStates: labelsStates
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

    private func rebuildLabelBuffers(visibleTiles: [PlaceTile], now: TimeInterval) {
        captureLabelStates()
        labelInputs.removeAll(keepingCapacity: true)
        drawLabels.removeAll(keepingCapacity: true)
        labelTilesList.removeAll(keepingCapacity: true)
        labelTileIndices.removeAll(keepingCapacity: true)
        labelStateIndices.removeAll(keepingCapacity: true)
        labelInputs.reserveCapacity(labelTiles.count * 8)
        var duplicateFlags: [UInt8] = []
        duplicateFlags.reserveCapacity(labelTiles.count * 8)
        var labelStates: [LabelState] = []
        labelStates.reserveCapacity(labelTiles.count * 8)
        var desiredVisibility: [UInt8] = []
        desiredVisibility.reserveCapacity(labelTiles.count * 8)
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
            for (index, meta) in cached.labelsMeta.enumerated() {
                labelStateIndices.append(LabelStateIndex(tileKey: cached.tileKey, localIndex: index))
                if seenLabelKeys.contains(meta.key) {
                    duplicateFlags.append(1)
                } else {
                    duplicateFlags.append(0)
                    seenLabelKeys.insert(meta.key)
                }
                labelStates.append(cached.labelsStates[index])
                desiredVisibility.append(1)
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
            for (index, meta) in cached.labelsMeta.enumerated() {
                labelStateIndices.append(LabelStateIndex(tileKey: cached.tileKey, localIndex: index))
                if seenLabelKeys.contains(meta.key) {
                    duplicateFlags.append(1)
                } else {
                    duplicateFlags.append(0)
                    seenLabelKeys.insert(meta.key)
                }
                labelStates.append(cached.labelsStates[index])
                desiredVisibility.append(0)
            }
            drawLabels.append(DrawLabels(
                labelsVerticesBuffer: cached.labelsVerticesBuffer,
                labelsCount: cached.labelsCount,
                labelsVerticesCount: cached.labelsVerticesCount
            ))
        }

        labelScreenCompute.copyDataToBuffer(inputs: labelInputs)
        labelInputsCount = labelInputs.count
        updateLabelStateBuffer(labelStates: labelStates)
        updateLabelDesiredVisibilityBuffer(desiredVisibility: desiredVisibility)

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

    private func captureLabelStates() {
        guard labelInputsCount > 0, labelStateIndices.isEmpty == false else {
            return
        }
        let count = min(labelInputsCount, labelStateIndices.count)
        let pointer = labelStateBuffer.contents().assumingMemoryBound(to: LabelState.self)
        for i in 0..<count {
            let index = labelStateIndices[i]
            guard var cached = labelTiles[index.tileKey],
                  index.localIndex < cached.labelsStates.count else {
                continue
            }
            cached.labelsStates[index.localIndex] = pointer[i]
            labelTiles[index.tileKey] = cached
        }
    }

    private func updateLabelStateBuffer(labelStates: [LabelState]) {
        let count = max(1, labelInputsCount)
        let needed = count * MemoryLayout<LabelState>.stride
        if labelStateBuffer.length < needed {
            labelStateBuffer = metalDevice.makeBuffer(
                length: needed,
                options: [.storageModeShared]
            )!
        }

        var states = labelStates
        if labelInputsCount == 0 {
            states = [LabelState(alpha: 0, target: 0, changeTime: 0, alphaStart: 0)]
        }
        let bytesCount = states.count * MemoryLayout<LabelState>.stride
        states.withUnsafeBytes { bytes in
            labelStateBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
        }

    }

    private func updateLabelDesiredVisibilityBuffer(desiredVisibility: [UInt8]) {
        let count = max(1, labelInputsCount)
        let needed = count * MemoryLayout<UInt8>.stride
        if labelDesiredVisibilityBuffer.length < needed {
            labelDesiredVisibilityBuffer = metalDevice.makeBuffer(
                length: needed,
                options: [.storageModeShared]
            )!
        }

        var visibility = desiredVisibility
        if labelInputsCount == 0 {
            visibility = [0]
        }
        if visibility.isEmpty == false {
            let bytesCount = visibility.count * MemoryLayout<UInt8>.stride
            visibility.withUnsafeBytes { bytes in
                labelDesiredVisibilityBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
            }
        }
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
    var labelsStates: [LabelState]
}

private struct LabelStateIndex {
    let tileKey: Tile
    let localIndex: Int
}
