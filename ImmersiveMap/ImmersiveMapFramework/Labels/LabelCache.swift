//
//  LabelCache.swift
//  ImmersiveMap
//
//  Created by Artem on 1/3/26.
//

import Foundation
import Metal
import simd

final class LabelCache {
    private let metalDevice: MTLDevice
    private let tilePointScreenCompute: TilePointScreenCompute

    private let roadLabelPadding: Float = 40.0
    private let maxRoadLabelInstancesPerPath: Int = 1
    
    // позиции лейблов на карте
    private var tilePointInputs: [TilePointInput] = []
    private var tilePointTileIndices: [UInt32] = []
    private var roadPathInputs: [TilePointInput] = []
    private var roadPathTileIndices: [UInt32] = []
    private var roadLabelBaseVertices: [LabelVertex] = []
    private var roadLabelBaseRanges: [LabelVerticesRange] = []
    private var roadLabelSizes: [SIMD2<Float>] = []
    private var roadGlyphInputs: [RoadGlyphInput] = []
    private var roadLabelGlyphRanges: [RoadLabelGlyphRange] = []
    private var roadLabelVertices: [LabelVertex] = []
    private var roadLabelRuntimeKeys: [UInt64] = []

    // Для отрисовки текста лейблов
    private(set) var drawLabels: [DrawLabels] = []
    
    
    // Этот буфер читается в шейдере, тут все состояния по каждому лейблу на карте
    private(set) var labelRuntimeBuffer: MTLBuffer
    private(set) var collisionInputBuffer: MTLBuffer
    private(set) var roadLabelRuntimeBuffer: MTLBuffer
    private(set) var roadLabelCollisionInputBuffer: MTLBuffer
    private(set) var roadLabelPlacementBuffer: MTLBuffer
    private(set) var roadLabelScreenPointsBuffer: MTLBuffer
    private(set) var roadGlyphInputBuffer: MTLBuffer
    private(set) var roadLabelGlyphRangesBuffer: MTLBuffer
    private(set) var roadPathRangesBuffer: MTLBuffer
    private(set) var roadLabelVerticesBuffer: MTLBuffer?
    
    
    private(set) var labelInputsCount: Int = 0
    private(set) var roadPathInputsCount: Int = 0
    private(set) var roadLabelInstancesCount: Int = 0
    private(set) var roadLabelGlyphCount: Int = 0
    private(set) var roadLabelVerticesCount: Int = 0
    
    // Он нужен для того, чтобы потом мы знали как построить буффер относительных сдвигов по flatPan
    private(set) var labelTilesList: [Tile] = []
    private var tileIndexByTile: [Tile: UInt32] = [:]

    private(set) var roadPathLabels: [RoadPathLabel] = []
    private(set) var roadPathRanges: [RoadPathRange] = []
    
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
        self.roadLabelRuntimeBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<LabelRuntimeState>.stride,
            options: [.storageModeShared]
        )!
        self.roadLabelCollisionInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<ScreenCollisionInput>.stride,
            options: [.storageModeShared]
        )!
        self.roadLabelPlacementBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<RoadGlyphPlacementOutput>.stride,
            options: [.storageModeShared]
        )!
        self.roadLabelScreenPointsBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<ScreenPointOutput>.stride,
            options: [.storageModeShared]
        )!
        self.roadGlyphInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<RoadGlyphInput>.stride,
            options: [.storageModeShared]
        )!
        self.roadPathRangesBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<RoadPathRangeGpu>.stride,
            options: [.storageModeShared]
        )!
        self.roadLabelGlyphRangesBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<RoadLabelGlyphRange>.stride,
            options: [.storageModeShared]
        )!
    }

    func rebuild(placeTilesContext: PlaceTilesContext, trackedTiles: [TileRetentionTracker.TrackedTile]) {
        let stateByKey = captureLabelStates()
        let roadStateByKey = captureRoadLabelStates()
        tilePointInputs.removeAll(keepingCapacity: true)
        tilePointTileIndices.removeAll(keepingCapacity: true)
        roadPathInputs.removeAll(keepingCapacity: true)
        roadPathTileIndices.removeAll(keepingCapacity: true)
        roadLabelBaseVertices.removeAll(keepingCapacity: true)
        roadLabelBaseRanges.removeAll(keepingCapacity: true)
        roadLabelSizes.removeAll(keepingCapacity: true)
        roadGlyphInputs.removeAll(keepingCapacity: true)
        roadLabelGlyphRanges.removeAll(keepingCapacity: true)
        roadLabelVertices.removeAll(keepingCapacity: true)
        drawLabels.removeAll(keepingCapacity: true)
        labelTilesList.removeAll(keepingCapacity: true)
        tileIndexByTile.removeAll(keepingCapacity: true)
        roadPathLabels.removeAll(keepingCapacity: true)
        roadPathRanges.removeAll(keepingCapacity: true)
        labelRuntimeKeys.removeAll(keepingCapacity: true)
        roadLabelRuntimeKeys.removeAll(keepingCapacity: true)
        
        var runtimeStates: [LabelRuntimeState] = []
        var seenLabelKeys: Set<UInt64> = []
        let placeTilesByTile = placeTilesContext.placeTilesByTile

        for tracked in trackedTiles {
            guard let placeTile = placeTilesByTile[tracked.tile] else {
                continue
            }
            let tileBuffers = placeTile.metalTile.tileBuffers
            let hasLabelPoints = tileBuffers.labelsCount > 0
            let hasRoadPaths = tileBuffers.roadPathInputs.isEmpty == false
            if hasLabelPoints == false && hasRoadPaths == false {
                continue
            }

            let tileIndex = tileIndex(for: placeTile.metalTile.tile)

            if hasLabelPoints {
                appendLabelInputs(tileIndex: tileIndex, tilePointInputs: tileBuffers.tilePointInputs)
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

            if hasRoadPaths {
                appendRoadPaths(tileIndex: tileIndex, tileBuffers: tileBuffers)
            }
        }

        tilePointScreenCompute.copyDataToBuffer(inputs: tilePointInputs, tileIndices: tilePointTileIndices)
        labelInputsCount = tilePointInputs.count
        roadPathInputsCount = roadPathInputs.count
        updateCollisionInputBuffer(inputs: tilePointInputs)
        updateLabelRuntimeBuffer(runtimeStates: runtimeStates)
        buildRoadLabelInstances(stateByKey: roadStateByKey)
    }

    func updateRoadPathCompute(_ compute: TilePointScreenCompute) {
        compute.copyDataToBuffer(inputs: roadPathInputs, tileIndices: roadPathTileIndices)
    }

    private func tileIndex(for tile: Tile) -> UInt32 {
        if let existing = tileIndexByTile[tile] {
            return existing
        }
        let tileIndex = UInt32(labelTilesList.count)
        labelTilesList.append(tile)
        tileIndexByTile[tile] = tileIndex
        return tileIndex
    }

    private func appendLabelInputs(tileIndex: UInt32, tilePointInputs: [TilePointInput]) {
        self.tilePointInputs.append(contentsOf: tilePointInputs)
        tilePointTileIndices.append(contentsOf: repeatElement(tileIndex, count: tilePointInputs.count))
    }

    private func appendRoadPaths(tileIndex: UInt32, tileBuffers: TileBuffers) {
        let startOffset = roadPathInputs.count
        roadPathInputs.append(contentsOf: tileBuffers.roadPathInputs)
        roadPathTileIndices.append(contentsOf: repeatElement(tileIndex, count: tileBuffers.roadPathInputs.count))

        let labelOffset = roadPathLabels.count
        roadPathLabels.append(contentsOf: tileBuffers.roadPathLabels)
        for range in tileBuffers.roadPathRanges {
            roadPathRanges.append(RoadPathRange(start: range.start + startOffset,
                                                count: range.count,
                                                labelIndex: range.labelIndex + labelOffset,
                                                anchorSegmentIndex: range.anchorSegmentIndex,
                                                anchorT: range.anchorT))
        }

        let baseVertexOffset = roadLabelBaseVertices.count
        roadLabelBaseVertices.append(contentsOf: tileBuffers.roadLabelBaseVertices)
        for range in tileBuffers.roadLabelVertexRanges {
            roadLabelBaseRanges.append(LabelVerticesRange(start: range.start + baseVertexOffset,
                                                          count: range.count))
        }
        roadLabelSizes.append(contentsOf: tileBuffers.roadLabelSizes)
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

    private func captureRoadLabelStates() -> [UInt64: LabelState] {
        guard roadLabelInstancesCount > 0, roadLabelRuntimeKeys.isEmpty == false else {
            return [:]
        }
        let count = min(roadLabelInstancesCount, roadLabelRuntimeKeys.count)
        let pointer = roadLabelRuntimeBuffer.contents().assumingMemoryBound(to: LabelRuntimeState.self)
        var states: [UInt64: LabelState] = [:]
        states.reserveCapacity(count)
        for i in 0..<count {
            let key = roadLabelRuntimeKeys[i]
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

    private func buildRoadLabelInstances(stateByKey: [UInt64: LabelState]) {
        let pathCount = roadPathRanges.count
        roadLabelInstancesCount = 0
        guard pathCount > 0 else {
            roadLabelInstancesCount = 0
            roadLabelGlyphCount = 0
            roadLabelVerticesCount = 0
            updateRoadLabelBuffers()
            return
        }

        var runtimeStates: [LabelRuntimeState] = []
        var seenKeys: Set<UInt64> = []
        var glyphInputs: [RoadGlyphInput] = []
        var glyphRanges: [RoadLabelGlyphRange] = []
        var vertices: [LabelVertex] = []
        var collisionInputs: [ScreenCollisionInput] = []
        var runtimeKeys: [UInt64] = []

        let estimatedInstances = pathCount * maxRoadLabelInstancesPerPath
        glyphRanges.reserveCapacity(estimatedInstances)
        runtimeStates.reserveCapacity(estimatedInstances)

        for (pathIndex, pathRange) in roadPathRanges.enumerated() {
            let labelIndex = pathRange.labelIndex
            if labelIndex < 0 || labelIndex >= roadLabelSizes.count {
                continue
            }

            let size = roadLabelSizes[labelIndex]
            let minLength = max(size.x + roadLabelPadding, size.x)
            guard labelIndex < roadLabelBaseRanges.count else {
                continue
            }

            let baseRange = roadLabelBaseRanges[labelIndex]
            let baseStart = baseRange.start
            let baseEnd = baseStart + baseRange.count
            let baseVertices = Array(roadLabelBaseVertices[baseStart..<baseEnd])
            let baseKey = roadPathLabels[labelIndex].key

            let glyphCount = baseRange.count / 6
            if glyphCount == 0 {
                continue
            }

            let instanceLimit = maxRoadLabelInstancesPerPath
            for instanceIndex in 0..<instanceLimit {
                let instanceId = roadLabelInstancesCount
                let glyphRangeStart = glyphInputs.count

                for glyphIndex in 0..<glyphCount {
                    let glyphStart = glyphIndex * 6
                    let glyphVertices = baseVertices[glyphStart..<(glyphStart + 6)]

                    var minX = Float.greatestFiniteMagnitude
                    var maxX = -Float.greatestFiniteMagnitude
                    var minY = Float.greatestFiniteMagnitude
                    var maxY = -Float.greatestFiniteMagnitude
                    for vertex in glyphVertices {
                        minX = min(minX, vertex.position.x)
                        maxX = max(maxX, vertex.position.x)
                        minY = min(minY, vertex.position.y)
                        maxY = max(maxY, vertex.position.y)
                    }
                    let glyphCenter = (minX + maxX) * 0.5
                    let glyphHalfSize = SIMD2<Float>((maxX - minX) * 0.5, (maxY - minY) * 0.5)

                    let glyphIndexGlobal = glyphInputs.count
                    glyphInputs.append(RoadGlyphInput(pathIndex: UInt32(pathIndex),
                                                      instanceIndex: UInt32(instanceIndex),
                                                      labelInstanceIndex: UInt32(instanceId),
                                                      glyphCenter: glyphCenter,
                                                      labelWidth: size.x,
                                                      spacing: 0.0,
                                                      minLength: minLength))

                    collisionInputs.append(ScreenCollisionInput(halfSize: glyphHalfSize,
                                                                radius: 0.0,
                                                                shapeType: .rect))

                    for vertex in glyphVertices {
                        vertices.append(LabelVertex(position: vertex.position,
                                                    uv: vertex.uv,
                                                    labelIndex: simd_int1(glyphIndexGlobal)))
                    }
                }

                let glyphRangeCount = glyphInputs.count - glyphRangeStart
                glyphRanges.append(RoadLabelGlyphRange(start: UInt32(glyphRangeStart),
                                                      count: UInt32(glyphRangeCount)))

                let instanceKey = roadLabelInstanceKey(baseKey: baseKey, instanceIndex: UInt32(instanceIndex))
                let duplicate = seenKeys.contains(instanceKey)
                let state = duplicate ? LabelState() : (stateByKey[instanceKey] ?? LabelState())
                runtimeStates.append(LabelRuntimeState(state: state,
                                                       duplicate: duplicate ? 1 : 0,
                                                       isRetained: 0,
                                                       tileIndex: 0))
                runtimeKeys.append(instanceKey)
                seenKeys.insert(instanceKey)
                roadLabelInstancesCount += 1
            }
        }

        roadGlyphInputs = glyphInputs
        roadLabelGlyphRanges = glyphRanges
        roadLabelVertices = vertices
        roadLabelGlyphCount = glyphInputs.count
        roadLabelVerticesCount = vertices.count
        roadLabelRuntimeKeys = runtimeKeys

        updateRoadLabelRuntimeBuffer(runtimeStates: runtimeStates)
        updateRoadLabelCollisionInputBuffer(inputs: collisionInputs)
        updateRoadLabelBuffers()
    }

    private func updateRoadLabelRuntimeBuffer(runtimeStates: [LabelRuntimeState]) {
        let count = max(1, roadLabelInstancesCount)
        let needed = count * MemoryLayout<LabelRuntimeState>.stride
        if roadLabelRuntimeBuffer.length < needed {
            roadLabelRuntimeBuffer = metalDevice.makeBuffer(
                length: needed,
                options: [.storageModeShared]
            )!
        }

        var states = runtimeStates
        if roadLabelInstancesCount == 0 {
            states = [LabelRuntimeState(state: LabelState(),
                                         duplicate: 0,
                                         isRetained: 0,
                                         tileIndex: 0)]
        }
        let bytesCount = states.count * MemoryLayout<LabelRuntimeState>.stride
        states.withUnsafeBytes { bytes in
            roadLabelRuntimeBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
        }
    }

    private func updateRoadLabelCollisionInputBuffer(inputs: [ScreenCollisionInput]) {
        let count = max(1, inputs.count)
        let needed = count * MemoryLayout<ScreenCollisionInput>.stride
        if roadLabelCollisionInputBuffer.length < needed {
            roadLabelCollisionInputBuffer = metalDevice.makeBuffer(
                length: needed,
                options: [.storageModeShared]
            )!
        }

        var collisionInputs = inputs
        if roadLabelGlyphCount == 0 {
            collisionInputs = [ScreenCollisionInput(halfSize: .zero, radius: 0.0, shapeType: .rect)]
        }
        let bytesCount = collisionInputs.count * MemoryLayout<ScreenCollisionInput>.stride
        collisionInputs.withUnsafeBytes { bytes in
            roadLabelCollisionInputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
        }
    }

    private func updateRoadLabelBuffers() {
        let glyphCount = max(1, roadLabelGlyphCount)
        let placementNeeded = glyphCount * MemoryLayout<RoadGlyphPlacementOutput>.stride
        if roadLabelPlacementBuffer.length < placementNeeded {
            roadLabelPlacementBuffer = metalDevice.makeBuffer(
                length: placementNeeded,
                options: [.storageModeShared]
            )!
        }

        let screenPointsNeeded = glyphCount * MemoryLayout<ScreenPointOutput>.stride
        if roadLabelScreenPointsBuffer.length < screenPointsNeeded {
            roadLabelScreenPointsBuffer = metalDevice.makeBuffer(
                length: screenPointsNeeded,
                options: [.storageModeShared]
            )!
        }

        let glyphInputsNeeded = glyphCount * MemoryLayout<RoadGlyphInput>.stride
        if roadGlyphInputBuffer.length < glyphInputsNeeded {
            roadGlyphInputBuffer = metalDevice.makeBuffer(
                length: glyphInputsNeeded,
                options: [.storageModeShared]
            )!
        }

        let pathRangesNeeded = max(1, roadPathRanges.count) * MemoryLayout<RoadPathRangeGpu>.stride
        if roadPathRangesBuffer.length < pathRangesNeeded {
            roadPathRangesBuffer = metalDevice.makeBuffer(
                length: pathRangesNeeded,
                options: [.storageModeShared]
            )!
        }

        let glyphRangesNeeded = max(1, roadLabelInstancesCount) * MemoryLayout<RoadLabelGlyphRange>.stride
        if roadLabelGlyphRangesBuffer.length < glyphRangesNeeded {
            roadLabelGlyphRangesBuffer = metalDevice.makeBuffer(
                length: glyphRangesNeeded,
                options: [.storageModeShared]
            )!
        }

        if roadLabelGlyphCount > 0 {
            roadGlyphInputs.withUnsafeBytes { bytes in
                roadGlyphInputBuffer.contents().copyMemory(from: bytes.baseAddress!,
                                                           byteCount: roadGlyphInputs.count * MemoryLayout<RoadGlyphInput>.stride)
            }
        }

        var gpuRanges: [RoadPathRangeGpu] = []
        if roadPathRanges.isEmpty {
            gpuRanges = [RoadPathRangeGpu(start: 0,
                                          count: 0,
                                          labelIndex: 0,
                                          anchorSegmentIndex: 0,
                                          anchorT: 0.0)]
        } else {
            gpuRanges.reserveCapacity(roadPathRanges.count)
            for range in roadPathRanges {
                gpuRanges.append(RoadPathRangeGpu(start: UInt32(range.start),
                                                  count: UInt32(range.count),
                                                  labelIndex: UInt32(range.labelIndex),
                                                  anchorSegmentIndex: UInt32(range.anchorSegmentIndex),
                                                  anchorT: range.anchorT))
            }
        }
        gpuRanges.withUnsafeBytes { bytes in
            roadPathRangesBuffer.contents().copyMemory(from: bytes.baseAddress!,
                                                       byteCount: gpuRanges.count * MemoryLayout<RoadPathRangeGpu>.stride)
        }

        var glyphRanges: [RoadLabelGlyphRange] = []
        if roadLabelGlyphRanges.isEmpty {
            glyphRanges = [RoadLabelGlyphRange(start: 0, count: 0)]
        } else {
            glyphRanges = roadLabelGlyphRanges
        }
        glyphRanges.withUnsafeBytes { bytes in
            roadLabelGlyphRangesBuffer.contents().copyMemory(from: bytes.baseAddress!,
                                                             byteCount: glyphRanges.count * MemoryLayout<RoadLabelGlyphRange>.stride)
        }

        if roadLabelVerticesCount > 0 {
            roadLabelVerticesBuffer = metalDevice.makeBuffer(
                bytes: roadLabelVertices,
                length: roadLabelVertices.count * MemoryLayout<LabelVertex>.stride,
                options: [.storageModeShared]
            )
        } else {
            roadLabelVerticesBuffer = nil
        }
    }

    private func roadLabelInstanceKey(baseKey: UInt64, instanceIndex: UInt32) -> UInt64 {
        var hash = baseKey
        hash ^= UInt64(instanceIndex) &* 1099511628211
        return hash
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
