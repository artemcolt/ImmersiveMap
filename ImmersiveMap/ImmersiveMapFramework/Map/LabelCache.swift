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
    
    // позиции лейблов на карте
    private var labelInputs: [LabelInput] = []
    
    // Для отрисовки текста лейблов
    private(set) var drawLabels: [DrawLabels] = []
    
    
    private let labelHoldSeconds: TimeInterval = 3.0
    
    // Тут кэш тайлов, которые отображаются или были на карте (удерживаемые определенное время тайлы)
    private var labelTiles: [Tile: CachedTileLabels] = [:]
    
    // Этот буфер читается в шейдере, тут все состояния по каждому лейблу на карте
    private(set) var labelRuntimeBuffer: MTLBuffer
    
    
    private(set) var labelInputsCount: Int = 0
    
    // Он нужен для того, чтобы потом мы знали как построить буффер относительных сдвигов по flatPan
    private(set) var labelTilesList: [Tile] = []
    
    // Чтобы потом из compute буффера прочитать новые состояния и записать их в кэш
    private var labelRuntimeKeys: [UInt64] = []

    init(metalDevice: MTLDevice, computeGlobeToScreen: LabelScreenCompute) {
        self.metalDevice = metalDevice
        self.labelScreenCompute = computeGlobeToScreen
        self.labelRuntimeBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<LabelRuntimeState>.stride,
            options: [.storageModeShared]
        )!
    }

    func update(placeTiles: [PlaceTile], now: TimeInterval) {
        var labelsNeedsRebuild = updateLabelCache(placeTiles: placeTiles, now: now)
        labelsNeedsRebuild = expireLabelTileCache(now: now) || labelsNeedsRebuild
        if labelsNeedsRebuild {
            rebuildLabelBuffers(now: now)
        }
    }

    private func updateLabelCache(placeTiles: [PlaceTile], now: TimeInterval) -> Bool {
        var changed = false
        for placeTile in placeTiles {
            let tile = placeTile.metalTile.tile
            let tileBuffers = placeTile.metalTile.tileBuffers

            // в тайле нету лэйблов
            let labelsCount = tileBuffers.labelsCount
            if labelsCount == 0 {
                continue
            }
            
            // тайл уже в кэше
            if var cached = labelTiles[tile] {
                cached.lastSeen = now
                labelTiles[tile] = cached
                continue
            }

            let meta = tileBuffers.labelsMeta
            labelTiles[tile] = CachedTileLabels(
                tile: tile,
                lastSeen: now,
                isRetained: false,
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

    private func expireLabelTileCache(now: TimeInterval) -> Bool {
        let keys = Array(labelTiles.keys)
        var expired: [Tile] = []
        expired.reserveCapacity(keys.count)
        var changed = false
        for tileKey in keys {
            guard var cached = labelTiles[tileKey] else {
                continue
            }
            if now - cached.lastSeen > labelHoldSeconds {
                expired.append(tileKey)
                continue
            }
            let retainedNow = cached.lastSeen < now
            if cached.isRetained != retainedNow {
                changed = true
                cached.isRetained = retainedNow
                labelTiles[tileKey] = cached
            }
        }

        if expired.isEmpty == false {
            for tileKey in expired {
                labelTiles.removeValue(forKey: tileKey)
            }
            changed = true
        }

        return changed
    }

    private func rebuildLabelBuffers(now: TimeInterval) {
        let stateByKey = captureLabelStates()
        labelInputs.removeAll(keepingCapacity: true)
        drawLabels.removeAll(keepingCapacity: true)
        labelTilesList.removeAll(keepingCapacity: true)
        labelRuntimeKeys.removeAll(keepingCapacity: true)
        
        var runtimeStates: [LabelRuntimeState] = []
        var seenLabelKeys: Set<UInt64> = []
        for cached in labelTiles.values.sorted(by: { ($0.isRetained ? 1 : 0) < ($1.isRetained ? 1 : 0) }) {
            let tileIndex = appendTileLabels(cached: cached)
            let retainedFlag: UInt32 = cached.isRetained ? 1 : 0
            for meta in cached.labelsMeta {
                let duplicate = seenLabelKeys.contains(meta.key)
                let state: LabelState
                if duplicate {
                    state = LabelState()
                } else {
                    state = stateByKey[meta.key] ?? LabelState()
                }
                
                
                runtimeStates.append(LabelRuntimeState(state: state,
                                                       duplicate: duplicate ? 1 : 0,
                                                       isRetained: retainedFlag,
                                                       tileIndex: tileIndex))
                labelRuntimeKeys.append(meta.key)
                seenLabelKeys.insert(meta.key)
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
    }

    private func appendTileLabels(cached: CachedTileLabels) -> UInt32 {
        let tileIndex = UInt32(labelTilesList.count)
        labelTilesList.append(cached.tile)
        labelInputs.append(contentsOf: cached.labelsInputs)
        return tileIndex
    }

    private func captureLabelStates() -> [UInt64: LabelState] {
        guard labelInputsCount > 0, labelRuntimeKeys.isEmpty == false else {
            return [:]
        }
        let count = min(labelInputsCount, labelRuntimeKeys.count)
        let pointer = labelRuntimeBuffer.contents().assumingMemoryBound(to: LabelRuntimeState.self)
        var states: [UInt64: LabelState] = [:]
        states.reserveCapacity(count)
        for i in 0..<count {
            let key = labelRuntimeKeys[i]
            let runtimeState = pointer[i]
            if runtimeState.duplicate == 0 {
                states[key] = pointer[i].state
            }
        }
        return states
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
            states = [LabelRuntimeState(state: LabelState(),
                                         duplicate: 0,
                                         isRetained: 0,
                                         tileIndex: 0)]
        }
        let bytesCount = states.count * MemoryLayout<LabelRuntimeState>.stride
        states.withUnsafeBytes { bytes in
            labelRuntimeBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
        }

    }
}

private struct CachedTileLabels {
    let tile: Tile
    var lastSeen: TimeInterval
    var isRetained: Bool
    let labelsInputs: [LabelInput]
    let labelsMeta: [GlobeLabelMeta]
    let labelsVerticesBuffer: MTLBuffer?
    let labelsCount: Int
    let labelsVerticesCount: Int
}
