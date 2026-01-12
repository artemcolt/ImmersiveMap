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

    func rebuild(placeTilesContext: PlaceTilesContext, trackedTiles: [TileRetentionTracker.TrackedTile]) {
        let stateByKey = captureLabelStates()
        labelInputs.removeAll(keepingCapacity: true)
        drawLabels.removeAll(keepingCapacity: true)
        labelTilesList.removeAll(keepingCapacity: true)
        labelRuntimeKeys.removeAll(keepingCapacity: true)
        
        var runtimeStates: [LabelRuntimeState] = []
        var seenLabelKeys: Set<UInt64> = []
        let placeTilesByTile = placeTilesContext.placeTilesByTile

        for tracked in trackedTiles {
            guard let placeTile = placeTilesByTile[tracked.tile] else {
                continue
            }
            let tileBuffers = placeTile.metalTile.tileBuffers
            if tileBuffers.labelsCount == 0 {
                continue
            }

            let tileIndex = appendTileLabels(tile: placeTile.metalTile.tile,
                                             labelsInputs: tileBuffers.labelsInputs)
            let retainedFlag: UInt32 = tracked.isRetained ? 1 : 0
            for meta in tileBuffers.labelsMeta {
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
                labelsVerticesBuffer: tileBuffers.labelsVerticesBuffer,
                labelsCount: tileBuffers.labelsCount,
                labelsVerticesCount: tileBuffers.labelsVerticesCount
            ))
        }

        labelScreenCompute.copyDataToBuffer(inputs: labelInputs)
        labelInputsCount = labelInputs.count
        updateLabelRuntimeBuffer(runtimeStates: runtimeStates)
    }

    private func appendTileLabels(tile: Tile, labelsInputs: [LabelInput]) -> UInt32 {
        let tileIndex = UInt32(labelTilesList.count)
        labelTilesList.append(tile)
        labelInputs.append(contentsOf: labelsInputs)
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
