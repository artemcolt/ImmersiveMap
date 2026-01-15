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
    private let tilePointScreenCompute: TilePointScreenCompute
    
    // позиции лейблов на карте
    private var tilePointInputs: [TilePointInput] = []
    private var tilePointTileIndices: [UInt32] = []
    
    // Для отрисовки текста лейблов
    private(set) var drawLabels: [DrawLabels] = []
    
    
    // Этот буфер читается в шейдере, тут все состояния по каждому лейблу на карте
    private(set) var labelRuntimeBuffer: MTLBuffer
    private(set) var collisionInputBuffer: MTLBuffer
    
    
    private(set) var labelInputsCount: Int = 0
    
    // Он нужен для того, чтобы потом мы знали как построить буффер относительных сдвигов по flatPan
    private(set) var labelTilesList: [Tile] = []
    
    // Чтобы потом из compute буффера прочитать новые состояния и записать их в кэш
    private var labelRuntimeKeys: [UInt64] = []

    init(metalDevice: MTLDevice, screenCompute: TilePointScreenCompute) {
        self.metalDevice = metalDevice
        self.tilePointScreenCompute = screenCompute
        self.labelRuntimeBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<LabelRuntimeState>.stride,
            options: [.storageModeShared]
        )!
        self.collisionInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<ScreenCollisionInput>.stride,
            options: [.storageModeShared]
        )!
    }

    func rebuild(placeTilesContext: PlaceTilesContext, trackedTiles: [TileRetentionTracker.TrackedTile]) {
        let stateByKey = captureLabelStates()
        tilePointInputs.removeAll(keepingCapacity: true)
        tilePointTileIndices.removeAll(keepingCapacity: true)
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
                                             tilePointInputs: tileBuffers.tilePointInputs)
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

        tilePointScreenCompute.copyDataToBuffer(inputs: tilePointInputs, tileIndices: tilePointTileIndices)
        labelInputsCount = tilePointInputs.count
        updateCollisionInputBuffer(inputs: tilePointInputs)
        updateLabelRuntimeBuffer(runtimeStates: runtimeStates)
    }

    private func appendTileLabels(tile: Tile, tilePointInputs: [TilePointInput]) -> UInt32 {
        let tileIndex = UInt32(labelTilesList.count)
        labelTilesList.append(tile)
        self.tilePointInputs.append(contentsOf: tilePointInputs)
        tilePointTileIndices.append(contentsOf: repeatElement(tileIndex, count: tilePointInputs.count))
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

    private func updateCollisionInputBuffer(inputs: [TilePointInput]) {
        let count = max(1, inputs.count)
        let needed = count * MemoryLayout<ScreenCollisionInput>.stride
        if collisionInputBuffer.length < needed {
            collisionInputBuffer = metalDevice.makeBuffer(
                length: needed,
                options: [.storageModeShared]
            )!
        }

        var collisionInputs: [ScreenCollisionInput] = []
        collisionInputs.reserveCapacity(max(1, inputs.count))
        if inputs.isEmpty {
            collisionInputs.append(ScreenCollisionInput(halfSize: .zero, radius: 0.0, shapeType: .rect))
        } else {
            for input in inputs {
                let halfSize = SIMD2<Float>(input.size.x * 0.5, input.size.y * 0.5)
                collisionInputs.append(ScreenCollisionInput(halfSize: halfSize,
                                                            radius: 0.0,
                                                            shapeType: .rect))
            }
        }

        let collisionBytes = collisionInputs.count * MemoryLayout<ScreenCollisionInput>.stride
        collisionInputs.withUnsafeBytes { bytes in
            collisionInputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: collisionBytes)
        }
    }
}
