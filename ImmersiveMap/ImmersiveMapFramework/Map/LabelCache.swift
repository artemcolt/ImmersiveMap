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
    private var labelStateByKey: [UInt64: CachedLabelState] = [:]
    private var lastVisibleTileKeys: Set<Tile> = []
    private(set) var labelRuntimeBuffer: MTLBuffer
    private(set) var labelInputsCount: Int = 0
    private(set) var labelTilesList: [Tile] = []
    private var labelRuntimeKeys: [UInt64] = []
    private(set) var labelTileIndices: [UInt32] = []
    private(set) var labelTileIndicesBuffer: MTLBuffer

    init(metalDevice: MTLDevice, computeGlobeToScreen: LabelScreenCompute) {
        self.metalDevice = metalDevice
        self.labelScreenCompute = computeGlobeToScreen
        self.labelRuntimeBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<LabelRuntimeState>.stride,
            options: [.storageModeShared]
        )!
        self.labelTileIndicesBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: [.storageModeShared]
        )!
    }

    func update(placeTiles: [PlaceTile], now: TimeInterval) {
        let currentVisibleKeys = Set(placeTiles.map { $0.metalTile.tile })
        var labelsNeedsRebuild = updateLabelCache(visibleTiles: placeTiles, now: now)
        labelsNeedsRebuild = expireLabelCache(now: now) || labelsNeedsRebuild
        if labelsNeedsRebuild == false {
            refreshLabelStateTimestamps(now: now)
        }
        _ = expireLabelStateCache(now: now)
        if currentVisibleKeys != lastVisibleTileKeys {
            labelsNeedsRebuild = true
            lastVisibleTileKeys = currentVisibleKeys
        }
        if labelsNeedsRebuild {
            rebuildLabelBuffers(placeTiles: placeTiles, now: now)
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

    private func expireLabelStateCache(now: TimeInterval) -> Bool {
        var expired: [UInt64] = []
        for (key, cached) in labelStateByKey {
            if now - cached.lastSeen > labelHoldSeconds {
                expired.append(key)
            }
        }
        if expired.isEmpty {
            return false
        }
        for key in expired {
            labelStateByKey.removeValue(forKey: key)
        }
        return true
    }

    private func refreshLabelStateTimestamps(now: TimeInterval) {
        guard labelRuntimeKeys.isEmpty == false else {
            return
        }
        for key in labelRuntimeKeys {
            if var cached = labelStateByKey[key] {
                cached.lastSeen = now
                labelStateByKey[key] = cached
            }
        }
    }

    private func rebuildLabelBuffers(placeTiles: [PlaceTile], now: TimeInterval) {
        captureLabelStates(now: now)
        labelInputs.removeAll(keepingCapacity: true)
        drawLabels.removeAll(keepingCapacity: true)
        labelTilesList.removeAll(keepingCapacity: true)
        labelTileIndices.removeAll(keepingCapacity: true)
        labelRuntimeKeys.removeAll(keepingCapacity: true)
        labelInputs.reserveCapacity(labelTiles.count * 8)
        var runtimeStates: [LabelRuntimeState] = []
        runtimeStates.reserveCapacity(labelTiles.count * 8)
        labelRuntimeKeys.reserveCapacity(labelTiles.count * 8)
        var seenLabelKeys: Set<UInt64> = []
        labelTilesList.reserveCapacity(labelTiles.count)
        labelTileIndices.reserveCapacity(labelTiles.count * 8)

        // Убираем все дубликарты из place tiles
        // берем только уникальные тайлы, чтобы собрать все лейблы
        var visible: [Tile] = []
        var visibleSet: Set<Tile> = []
        visible.reserveCapacity(placeTiles.count)
        visibleSet.reserveCapacity(placeTiles.count)
        for placeTile in placeTiles {
            let tile = placeTile.metalTile.tile
            if visibleSet.insert(tile).inserted {
                visible.append(tile)
            }
        }

        for tile in visible {
            guard let cached = labelTiles[tile] else {
                continue
            }
            _ = appendTileLabels(cached: cached)
            for meta in cached.labelsMeta {
                let state = stateForKey(meta.key, now: now)
                runtimeStates.append(LabelRuntimeState(state: state,
                                                       duplicate: seenLabelKeys.contains(meta.key) ? 1 : 0,
                                                       isRetained: 0))
                labelRuntimeKeys.append(meta.key)
                seenLabelKeys.insert(meta.key)
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
                let state = stateForKey(meta.key, now: now)
                runtimeStates.append(LabelRuntimeState(state: state, duplicate: seenLabelKeys.contains(meta.key) ? 1 : 0, isRetained: 1))
                labelRuntimeKeys.append(meta.key)
            }
            drawLabels.append(DrawLabels(
                labelsVerticesBuffer: cached.labelsVerticesBuffer,
                labelsCount: cached.labelsCount,
                labelsVerticesCount: cached.labelsVerticesCount
            ))
        }

        labelScreenCompute.copyDataToBuffer(inputs: labelInputs)
        labelInputsCount = labelInputs.count
        updateLabelRuntimeBuffer(runtimeStates: runtimeStates)

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

    private func captureLabelStates(now: TimeInterval) {
        guard labelInputsCount > 0, labelRuntimeKeys.isEmpty == false else {
            return
        }
        let count = min(labelInputsCount, labelRuntimeKeys.count)
        let pointer = labelRuntimeBuffer.contents().assumingMemoryBound(to: LabelRuntimeState.self)
        for i in 0..<count {
            let key = labelRuntimeKeys[i]
            labelStateByKey[key] = CachedLabelState(state: pointer[i].state, lastSeen: now)
        }
    }

    private func updateLabelRuntimeBuffer(runtimeStates: [LabelRuntimeState]) {
        let count = max(1, labelInputsCount)
        let needed = count * MemoryLayout<LabelRuntimeState>.stride
        if labelRuntimeBuffer.length < needed {
            labelRuntimeBuffer = metalDevice.makeBuffer(
                length: needed,
                options: [.storageModeShared]
            )!
        }

        var states = runtimeStates
        if labelInputsCount == 0 {
            states = [LabelRuntimeState(state: LabelState(alpha: 0, target: 0, changeTime: 0, alphaStart: 0),
                                         duplicate: 0,
                                         isRetained: 0)]
        }
        let bytesCount = states.count * MemoryLayout<LabelRuntimeState>.stride
        states.withUnsafeBytes { bytes in
            labelRuntimeBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
        }

    }

    private func stateForKey(_ key: UInt64, now: TimeInterval) -> LabelState {
        if var cached = labelStateByKey[key] {
            cached.lastSeen = now
            labelStateByKey[key] = cached
            return cached.state
        }
        let state = LabelState(alpha: 0, target: 0, changeTime: Float(now), alphaStart: 0)
        labelStateByKey[key] = CachedLabelState(state: state, lastSeen: now)
        return state
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

private struct CachedLabelState {
    var state: LabelState
    var lastSeen: TimeInterval
}
