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

    private let roadLabelRepeatDistancePx: Float = 100.0
    private let maxRoadLabelInstancesPerPath: Int = 12
    private let roadLabelTileExtent: Float = 4096.0
    
    // позиции лейблов на карте
    private var tilePointInputs: [TilePointInput] = []
    private var tilePointTileIndices: [UInt32] = []
    private var roadPathInputs: [TilePointInput] = []
    private var roadPathTileIndices: [UInt32] = []
    private var roadLabelBaseVertices: [LabelVertex] = []
    private var roadLabelBaseRanges: [LabelVerticesRange] = []
    private var roadLabelGlyphBounds: [SIMD4<Float>] = []
    private var roadLabelGlyphBoundRanges: [LabelGlyphRange] = []
    private var roadLabelSizes: [SIMD2<Float>] = []
    private var roadGlyphInputs: [RoadGlyphInput] = []
    private var roadLabelGlyphRanges: [RoadLabelGlyphRange] = []
    private var roadLabelVertices: [LabelVertex] = []
    private var roadLabelAnchors: [RoadLabelAnchor] = []
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
    private(set) var roadLabelAnchorBuffer: MTLBuffer
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
        self.roadLabelAnchorBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<RoadLabelAnchor>.stride,
            options: [.storageModeShared]
        )!
        self.roadLabelGlyphRangesBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<RoadLabelGlyphRange>.stride,
            options: [.storageModeShared]
        )!
    }

    func rebuild(placeTilesContext: PlaceTilesContext,
                 trackedTiles: [TileRetentionTracker.TrackedTile],
                 tileUnitsPerPixel: Float) {
        let stateByKey = captureLabelStates()
        let roadStateByKey = captureRoadLabelStates()
        tilePointInputs.removeAll(keepingCapacity: true)
        tilePointTileIndices.removeAll(keepingCapacity: true)
        roadPathInputs.removeAll(keepingCapacity: true)
        roadPathTileIndices.removeAll(keepingCapacity: true)
        roadLabelBaseVertices.removeAll(keepingCapacity: true)
        roadLabelBaseRanges.removeAll(keepingCapacity: true)
        roadLabelGlyphBounds.removeAll(keepingCapacity: true)
        roadLabelGlyphBoundRanges.removeAll(keepingCapacity: true)
        roadLabelSizes.removeAll(keepingCapacity: true)
        roadGlyphInputs.removeAll(keepingCapacity: true)
        roadLabelGlyphRanges.removeAll(keepingCapacity: true)
        roadLabelVertices.removeAll(keepingCapacity: true)
        roadLabelAnchors.removeAll(keepingCapacity: true)
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
        buildRoadLabelInstances(stateByKey: roadStateByKey, tileUnitsPerPixel: tileUnitsPerPixel)
    }

    func updateRoadPathCompute(_ compute: TilePointScreenCompute) {
        compute.copyDataToBuffer(inputs: roadPathInputs, tileIndices: roadPathTileIndices)
    }

    func rebuildRoadLabelInstances(tileUnitsPerPixel: Float) {
        let roadStateByKey = captureRoadLabelStates()
        roadGlyphInputs.removeAll(keepingCapacity: true)
        roadLabelGlyphRanges.removeAll(keepingCapacity: true)
        roadLabelVertices.removeAll(keepingCapacity: true)
        roadLabelAnchors.removeAll(keepingCapacity: true)
        roadLabelRuntimeKeys.removeAll(keepingCapacity: true)
        buildRoadLabelInstances(stateByKey: roadStateByKey, tileUnitsPerPixel: tileUnitsPerPixel)
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
                                                labelIndex: range.labelIndex + labelOffset))
        }

        let baseVertexOffset = roadLabelBaseVertices.count
        roadLabelBaseVertices.append(contentsOf: tileBuffers.roadLabelBaseVertices)
        for range in tileBuffers.roadLabelVertexRanges {
            roadLabelBaseRanges.append(LabelVerticesRange(start: range.start + baseVertexOffset,
                                                          count: range.count))
        }
        let glyphBoundsOffset = roadLabelGlyphBounds.count
        roadLabelGlyphBounds.append(contentsOf: tileBuffers.roadLabelGlyphBounds)
        for range in tileBuffers.roadLabelGlyphBoundRanges {
            roadLabelGlyphBoundRanges.append(LabelGlyphRange(start: range.start + glyphBoundsOffset,
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

    private func buildRoadLabelInstances(stateByKey: [UInt64: LabelState],
                                         tileUnitsPerPixel: Float) {
        let pathCount = roadPathRanges.count
        roadLabelInstancesCount = 0
        guard pathCount > 0 else {
            roadLabelInstancesCount = 0
            roadLabelGlyphCount = 0
            roadLabelVerticesCount = 0
            updateRoadLabelBuffers()
            return
        }

        let safeTileUnitsPerPixel = max(0.0001, tileUnitsPerPixel)
        let repeatDistanceTile = max(0.0, roadLabelRepeatDistancePx * safeTileUnitsPerPixel)

        var runtimeStates: [LabelRuntimeState] = []
        var seenKeys: Set<UInt64> = []
        var glyphInputs: [RoadGlyphInput] = []
        var glyphRanges: [RoadLabelGlyphRange] = []
        var vertices: [LabelVertex] = []
        var collisionInputs: [ScreenCollisionInput] = []
        var runtimeKeys: [UInt64] = []
        var anchors: [RoadLabelAnchor] = []

        let estimatedInstances = pathCount * maxRoadLabelInstancesPerPath
        glyphRanges.reserveCapacity(estimatedInstances)
        runtimeStates.reserveCapacity(estimatedInstances)
        anchors.reserveCapacity(estimatedInstances)

        func tilePoint(at index: Int) -> SIMD2<Float> {
            let uv = roadPathInputs[index].uv
            return uv * roadLabelTileExtent
        }

        for (pathIndex, pathRange) in roadPathRanges.enumerated() {
            let labelIndex = pathRange.labelIndex
            if labelIndex < 0 || labelIndex >= roadLabelSizes.count {
                continue
            }
            guard labelIndex < roadLabelBaseRanges.count else {
                continue
            }
            guard labelIndex < roadLabelGlyphBoundRanges.count else {
                continue
            }
            let size = roadLabelSizes[labelIndex]
            let labelWidthTile = size.x * safeTileUnitsPerPixel
            guard labelWidthTile > 0.0 else {
                continue
            }
            let minLengthPx = size.x

            let start = pathRange.start
            let count = pathRange.count
            if count < 2 {
                continue
            }

            var segmentLengths: [Float] = []
            segmentLengths.reserveCapacity(count - 1)
            var totalLength: Float = 0.0
            var prev = tilePoint(at: start)
            for i in 1..<count {
                let current = tilePoint(at: start + i)
                let length = simd_length(current - prev)
                segmentLengths.append(length)
                totalLength += length
                prev = current
            }

            guard totalLength >= labelWidthTile else {
                continue
            }

            var anchorDistances = buildRoadLabelAnchors(totalLength: totalLength,
                                                        labelWidth: labelWidthTile,
                                                        repeatDistance: repeatDistanceTile)
            if anchorDistances.isEmpty {
                continue
            }
            anchorDistances.sort()
            if anchorDistances.count > maxRoadLabelInstancesPerPath {
                anchorDistances = limitAnchors(anchorDistances,
                                               totalLength: totalLength,
                                               limit: maxRoadLabelInstancesPerPath)
            }

            var anchorSegmentsWithDistance: [(distance: Float, anchor: RoadLabelAnchor)] = []
            anchorSegmentsWithDistance.reserveCapacity(anchorDistances.count)
            var segmentIndex = 0
            var accumulated: Float = 0.0
            var segmentLength = segmentLengths.first ?? 0.0
            for distance in anchorDistances {
                let clampedDistance = min(max(distance, 0.0), totalLength)
                while segmentIndex < segmentLengths.count - 1,
                      accumulated + segmentLength < clampedDistance {
                    accumulated += segmentLength
                    segmentIndex += 1
                    segmentLength = segmentLengths[segmentIndex]
                }

                var t: Float = 0.0
                if segmentLength > 0.0 {
                    t = (clampedDistance - accumulated) / segmentLength
                }
                t = min(max(t, 0.0), 1.0)
                let anchor = RoadLabelAnchor(pathIndex: UInt32(pathIndex),
                                             segmentIndex: UInt32(segmentIndex),
                                             t: t)
                anchorSegmentsWithDistance.append((distance: clampedDistance, anchor: anchor))
            }

            let baseRange = roadLabelBaseRanges[labelIndex]
            let glyphBoundsRange = roadLabelGlyphBoundRanges[labelIndex]
            let glyphCount = min(baseRange.count / 6, glyphBoundsRange.count)
            if glyphCount == 0 {
                continue
            }
            let baseStart = baseRange.start
            let boundsStart = glyphBoundsRange.start
            let baseVerticesEnd = baseStart + glyphCount * 6
            let boundsEnd = boundsStart + glyphCount
            if baseVerticesEnd > roadLabelBaseVertices.count || boundsEnd > roadLabelGlyphBounds.count {
                continue
            }
            let baseKey = roadPathLabels[labelIndex].key
            let centerDistance = totalLength * 0.5
            let anchorSegments = anchorSegmentsWithDistance.sorted {
                abs($0.distance - centerDistance) < abs($1.distance - centerDistance)
            }.map { $0.anchor }

            for (instanceIndex, anchor) in anchorSegments.enumerated() {
                let instanceId = roadLabelInstancesCount
                let glyphRangeStart = glyphInputs.count

                for glyphIndex in 0..<glyphCount {
                    let glyphStart = baseStart + glyphIndex * 6
                    let glyphVertices = roadLabelBaseVertices[glyphStart..<(glyphStart + 6)]
                    let bounds = roadLabelGlyphBounds[boundsStart + glyphIndex]
                    let minX = bounds.x
                    let maxX = bounds.y
                    let minY = bounds.z
                    let maxY = bounds.w
                    let glyphCenter = (minX + maxX) * 0.5
                    let glyphHalfSize = SIMD2<Float>((maxX - minX) * 0.5, (maxY - minY) * 0.5)

                    let glyphIndexGlobal = glyphInputs.count
                    glyphInputs.append(RoadGlyphInput(pathIndex: UInt32(pathIndex),
                                                      instanceIndex: UInt32(instanceIndex),
                                                      labelInstanceIndex: UInt32(instanceId),
                                                      glyphCenter: glyphCenter,
                                                      labelWidth: size.x,
                                                      spacing: roadLabelRepeatDistancePx,
                                                      minLength: minLengthPx))

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
                anchors.append(anchor)
                roadLabelInstancesCount += 1
            }
        }

        roadGlyphInputs = glyphInputs
        roadLabelGlyphRanges = glyphRanges
        roadLabelVertices = vertices
        roadLabelAnchors = anchors
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

        let anchorsNeeded = max(1, roadLabelInstancesCount) * MemoryLayout<RoadLabelAnchor>.stride
        if roadLabelAnchorBuffer.length < anchorsNeeded {
            roadLabelAnchorBuffer = metalDevice.makeBuffer(
                length: anchorsNeeded,
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
                                          count: 0)]
        } else {
            gpuRanges.reserveCapacity(roadPathRanges.count)
            for range in roadPathRanges {
                gpuRanges.append(RoadPathRangeGpu(start: UInt32(range.start),
                                                  count: UInt32(range.count)))
            }
        }
        gpuRanges.withUnsafeBytes { bytes in
            roadPathRangesBuffer.contents().copyMemory(from: bytes.baseAddress!,
                                                       byteCount: gpuRanges.count * MemoryLayout<RoadPathRangeGpu>.stride)
        }

        var anchorData: [RoadLabelAnchor] = []
        if roadLabelAnchors.isEmpty {
            anchorData = [RoadLabelAnchor(pathIndex: 0, segmentIndex: 0, t: 0.0)]
        } else {
            anchorData = roadLabelAnchors
        }
        anchorData.withUnsafeBytes { bytes in
            roadLabelAnchorBuffer.contents().copyMemory(from: bytes.baseAddress!,
                                                        byteCount: anchorData.count * MemoryLayout<RoadLabelAnchor>.stride)
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

    private func buildRoadLabelAnchors(totalLength: Float,
                                       labelWidth: Float,
                                       repeatDistance: Float) -> [Float] {
        guard totalLength >= labelWidth else {
            return []
        }

        let minCenterSpacing = labelWidth + repeatDistance
        var anchors: [Float] = []
        var stack: [(Float, Float)] = [(0.0, totalLength)]

        while let segment = stack.popLast() {
            let start = segment.0
            let end = segment.1
            let length = end - start
            if length < labelWidth {
                continue
            }

            let mid = (start + end) * 0.5
            anchors.append(mid)

            let leftEnd = mid - minCenterSpacing
            if leftEnd - start >= labelWidth {
                stack.append((start, leftEnd))
            }

            let rightStart = mid + minCenterSpacing
            if end - rightStart >= labelWidth {
                stack.append((rightStart, end))
            }
        }

        return anchors
    }

    private func limitAnchors(_ anchors: [Float], totalLength: Float, limit: Int) -> [Float] {
        guard anchors.count > limit else {
            return anchors
        }

        let center = totalLength * 0.5
        let prioritized = anchors.sorted { abs($0 - center) < abs($1 - center) }
        let selected = prioritized.prefix(limit)
        return Array(selected).sorted()
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
