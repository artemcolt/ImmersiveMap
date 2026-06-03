// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  BaseLabelPrepareSubsystem.swift
//  ImmersiveMap
//

import Foundation
import Metal
import simd

final class BaseLabelPrepareSubsystem: RenderSubsystem {
    let name: String = "BaseLabels"

    private let baseLabelCache: BaseLabelCache
    private let roadLabelCache: RoadLabelCache?
    private let tilePointScreenProjector = TilePointScreenProjector()
    private let baseScreenCompute: TilePointScreenCompute
    private let roadPathScreenCompute: TilePointScreenCompute
    private let roadPlacementCalculator: RoadLabelPlacementCalculator
    private let collisionFlagsBufferStore: FrameSlottedDynamicMetalBuffer<UInt32>
    private let presentationStateStore = BaseLabelPresentationStateStore()
    private let roadPresentationStateStore = BaseLabelPresentationStateStore()
    private let roadRuntimeMetaBufferStore: FrameSlottedDynamicMetalBuffer<LabelRuntimeMeta>
    private let fallbackTileOriginDataBufferStore: FrameSlottedDynamicMetalBuffer<FlatTileOriginData>
    private let fadeInSeconds: TimeInterval
    private let fadeOutSeconds: TimeInterval
    private let orientationScoreEpsilon: Float
    private let maxGlyphTurnRadians: Float
    private let collisionGridCellSizePx: Float
    private let collisionsEnabled: Bool = true
    private let visibilityRefreshInterval: TimeInterval = 0.2
    private let collisionGroupBudgetPerFrame: Int = 256

    private var sourceEntriesVersionTracker = StagedHashChangeTracker()
    private var projectionVersionTracker = StagedHashChangeTracker()
    private var roadOrientationByInstanceKey: [UInt64: Bool] = [:]
    private var roadDrawLabels: [DrawRoadLabels] = []
    private var visibilityTopologyGeneration: UInt64 = 0
    private var latestCameraFingerprint: Int = 0
    private var publishedVisibilityCameraFingerprint: Int = 0
    private var lastVisibilityCycleStartTime: TimeInterval = -.greatestFiniteMagnitude
    private var publishedBaseCollisionFlags: [UInt32] = []
    private var publishedRoadInstanceVisibility: [Bool] = []
    private var visibilityCycle: VisibilityCycle?

    private let roadPriorityBase: Int = 1_000_000_000

    init(baseLabelCache: BaseLabelCache,
         roadLabelCache: RoadLabelCache? = nil,
         metalDevice: MTLDevice,
         library: MTLLibrary,
         settings: ImmersiveMapSettings.LabelSettings = ImmersiveMapSettings.default.labels) {
        self.baseLabelCache = baseLabelCache
        self.roadLabelCache = roadLabelCache
        self.baseScreenCompute = TilePointScreenCompute(metalDevice: metalDevice, library: library)
        self.roadPathScreenCompute = TilePointScreenCompute(metalDevice: metalDevice, library: library)
        self.roadPlacementCalculator = RoadLabelPlacementCalculator(pipeline: RoadLabelPlacementPipeline(metalDevice: metalDevice,
                                                                                                         library: library))
        self.collisionFlagsBufferStore = FrameSlottedDynamicMetalBuffer(metalDevice: metalDevice,
                                                                        slotsCount: InFlightFramePool.inFlightFramesCount,
                                                                        options: [.storageModeShared])
        self.roadRuntimeMetaBufferStore = FrameSlottedDynamicMetalBuffer(metalDevice: metalDevice,
                                                                         slotsCount: InFlightFramePool.inFlightFramesCount,
                                                                         options: [.storageModeShared])
        self.fallbackTileOriginDataBufferStore = FrameSlottedDynamicMetalBuffer(metalDevice: metalDevice,
                                                                                slotsCount: InFlightFramePool.inFlightFramesCount,
                                                                                options: [.storageModeShared])
        self.fadeInSeconds = settings.base.fadeInSeconds
        self.fadeOutSeconds = settings.base.fadeOutSeconds
        self.orientationScoreEpsilon = settings.road.orientationScoreEpsilon
        self.maxGlyphTurnRadians = settings.road.maxGlyphTurnRadians
        self.collisionGridCellSizePx = max(8.0, settings.base.gridCellSizePx)
    }

    convenience init(baseLabelCache: BaseLabelCache,
                     roadLabelCache: RoadLabelCache? = nil,
                     metalDevice: MTLDevice,
                     settings: ImmersiveMapSettings.LabelSettings = ImmersiveMapSettings.default.labels) {
        let bundle = Bundle.module
        let library = RendererSetup.makeLibrary(metalDevice: metalDevice, bundle: bundle)
        self.init(baseLabelCache: baseLabelCache,
                  roadLabelCache: roadLabelCache,
                  metalDevice: metalDevice,
                  library: library,
                  settings: settings)
    }

    convenience init(baseLabelCache: BaseLabelCache,
                     roadLabelCache: RoadLabelCache? = nil,
                     metalDevice: MTLDevice,
                     library: MTLLibrary,
                     gridCellSizePx: Float,
                     fadeInSeconds: TimeInterval = ImmersiveMapSettings.default.labels.base.fadeInSeconds,
                     fadeOutSeconds: TimeInterval = ImmersiveMapSettings.default.labels.base.fadeOutSeconds,
                     roadGridCellSizePx: Float = ImmersiveMapSettings.default.labels.road.gridCellSizePx,
                     orientationScoreEpsilon: Float = ImmersiveMapSettings.default.labels.road.orientationScoreEpsilon,
                     maxGlyphTurnRadians: Float = ImmersiveMapSettings.default.labels.road.maxGlyphTurnRadians) {
        var settings = ImmersiveMapSettings.default.labels
        settings.base.gridCellSizePx = gridCellSizePx
        settings.base.fadeInSeconds = fadeInSeconds
        settings.base.fadeOutSeconds = fadeOutSeconds
        settings.road.gridCellSizePx = roadGridCellSizePx
        settings.road.orientationScoreEpsilon = orientationScoreEpsilon
        settings.road.maxGlyphTurnRadians = maxGlyphTurnRadians
        self.init(baseLabelCache: baseLabelCache,
                  roadLabelCache: roadLabelCache,
                  metalDevice: metalDevice,
                  library: library,
                  settings: settings)
    }

    convenience init(baseLabelCache: BaseLabelCache,
                     roadLabelCache: RoadLabelCache? = nil,
                     metalDevice: MTLDevice,
                     gridCellSizePx: Float,
                     fadeInSeconds: TimeInterval = ImmersiveMapSettings.default.labels.base.fadeInSeconds,
                     fadeOutSeconds: TimeInterval = ImmersiveMapSettings.default.labels.base.fadeOutSeconds,
                     roadGridCellSizePx: Float = ImmersiveMapSettings.default.labels.road.gridCellSizePx,
                     orientationScoreEpsilon: Float = ImmersiveMapSettings.default.labels.road.orientationScoreEpsilon,
                     maxGlyphTurnRadians: Float = ImmersiveMapSettings.default.labels.road.maxGlyphTurnRadians) {
        let bundle = Bundle.module
        let library = RendererSetup.makeLibrary(metalDevice: metalDevice, bundle: bundle)
        self.init(baseLabelCache: baseLabelCache,
                  roadLabelCache: roadLabelCache,
                  metalDevice: metalDevice,
                  library: library,
                  gridCellSizePx: gridCellSizePx,
                  fadeInSeconds: fadeInSeconds,
                  fadeOutSeconds: fadeOutSeconds,
                  roadGridCellSizePx: roadGridCellSizePx,
                  orientationScoreEpsilon: orientationScoreEpsilon,
                  maxGlyphTurnRadians: maxGlyphTurnRadians)
    }

    func update(frameContext: FrameContext) {
        let placeTileTrackingState = frameContext.sharedState.placeTileTrackingState
        let projectionIndexState = frameContext.sharedState.tileProjectionIndexState
        let sourceEntries = BaseLabelSourceEntry.build(from: placeTileTrackingState.placeTiles)
        latestCameraFingerprint = makeVisibilityCameraFingerprint(frameContext: frameContext)

        let trackedTilesChanged = sourceEntriesVersionTracker.stage(BaseLabelSourceEntry.makeHash(sourceEntries))
        let projectionChanged = projectionVersionTracker.stage(Int(truncatingIfNeeded: projectionIndexState.sourceIndexVersion))
        if trackedTilesChanged || projectionChanged {
            let previousBaseVisibilityByKey = makePublishedBaseVisibilityByKey()
            let previousRoadVisibilityByKey = makePublishedRoadVisibilityByKey()
            baseLabelCache.synchronize(sourceEntries: sourceEntries,
                                       tileIndexAllocator: projectionIndexState.tileIndexAllocator,
                                       trackedTilesChanged: trackedTilesChanged,
                                       projectionChanged: projectionChanged)
            roadLabelCache?.synchronize(sourceEntries: sourceEntries,
                                        tileIndexAllocator: projectionIndexState.tileIndexAllocator,
                                        trackedTilesChanged: trackedTilesChanged,
                                        projectionChanged: projectionChanged)
            refreshGpuTopology(trackedTilesChanged: trackedTilesChanged,
                               projectionChanged: projectionChanged)
            visibilityTopologyGeneration &+= 1
            reseedPublishedVisibilityState(baseVisibilityByKey: previousBaseVisibilityByKey,
                                          roadVisibilityByKey: previousRoadVisibilityByKey)
            visibilityCycle = nil
            if trackedTilesChanged {
                sourceEntriesVersionTracker.commitPending()
            }
            if projectionChanged {
                projectionVersionTracker.commitPending()
            }
        }

        if collisionsEnabled {
            maybeStartVisibilityCycle(frameContext: frameContext, forceRestart: trackedTilesChanged || projectionChanged)
            advanceVisibilityCycleIfNeeded(frameContext: frameContext)
        } else {
            visibilityCycle = nil
            publishedBaseCollisionFlags = baseLabelCache.presentationInputs.map { input in
                input.isValid ? UInt32(0) : UInt32(1)
            }
            if let roadLabelCache {
                publishedRoadInstanceVisibility = Array(repeating: true, count: roadLabelCache.instanceKeys.count)
            } else {
                publishedRoadInstanceVisibility = []
            }
            publishedVisibilityCameraFingerprint = latestCameraFingerprint
        }

        let collisionFlagsBuffer = makeCollisionFlagsBuffer(frameContext: frameContext,
                                                            collisionFlags: publishedBaseCollisionFlags,
                                                            expectedCount: baseLabelCache.activeLabelSpanCount)

        let overviewFadeAlpha = LowZoomOverviewFade.alpha(for: frameContext.zoom)
        let fadeResolution = presentationStateStore.resolveAlphas(inputs: baseLabelCache.presentationInputs,
                                                                  collisionFlags: publishedBaseCollisionFlags,
                                                                  time: frameContext.time,
                                                                  frameIndex: frameContext.frameIndex,
                                                                  fadeInSeconds: fadeInSeconds,
                                                                  fadeOutSeconds: fadeOutSeconds)
        baseLabelCache.updateFadeAlphas(fadeResolution.fadeAlphas,
                                        multiplier: overviewFadeAlpha)
        let hasPendingVisibilityRefresh = collisionsEnabled && latestCameraFingerprint != publishedVisibilityCameraFingerprint
        publishBaseLabelState(frameContext: frameContext,
                              hasActiveFadeAnimations: fadeResolution.hasActiveAnimations,
                              hasActiveVisibilityCycle: hasPendingVisibilityRefresh)
        frameContext.sharedState.baseLabelState.screenPositionsBuffer = nil
        frameContext.sharedState.baseLabelState.collisionFlagsBuffer = collisionFlagsBuffer

        let roadState = buildRoadLabelState(frameContext: frameContext,
                                            roadVisibility: publishedRoadInstanceVisibility)
        frameContext.sharedState.roadLabelState = roadState

        frameContext.services.diagnostics.setCounter(.baseLabelCount, value: baseLabelCache.labelInputsCount)
        frameContext.services.diagnostics.setCounter(.roadLabelGlyphCount, value: roadState.glyphCount)
        frameContext.services.diagnostics.setCounter(.roadLabelInstanceCount, value: roadState.instanceCount)
    }

    func prepareGPU(frameContext: FrameContext, resourceRegistry _: RenderResourceRegistry) {
        let tileOriginDataBuffer = resolveTileOriginDataBuffer(frameContext: frameContext)
        let basePointCount = baseLabelCache.activeLabelSpanCount
        if basePointCount > 0 {
            baseScreenCompute.run(frameContext: frameContext,
                                  pointCount: basePointCount,
                                  tileOriginDataBuffer: tileOriginDataBuffer)
            frameContext.sharedState.baseLabelState.screenPositionsBuffer = baseScreenCompute.outputBuffer(slot: frameContext.frameSlotIndex,
                                                                                                           count: basePointCount)
        }

        guard let roadLabelCache,
              roadLabelCache.orderedTileRecords.isEmpty == false else {
            return
        }

        guard let commandBuffer = frameContext.commandBuffer else {
            return
        }

        var drawBatches: [DrawRoadLabels] = []
        let staticBatches = frameContext.sharedState.roadLabelState.drawLabels
        let records = roadLabelCache.orderedTileRecords
        drawBatches.reserveCapacity(records.count)

        for (index, record) in records.enumerated() {
            guard record.pathPointCount > 0,
                  record.glyphCount > 0,
                  let pathInputsBuffer = record.pathInputsBuffer,
                  let pathRangesBuffer = record.pathRangesBuffer,
                  let anchorsBuffer = record.anchorsBuffer,
                  let glyphInputsBuffer = record.glyphInputsBuffer,
                  let collisionInputsBuffer = record.collisionInputsBuffer else {
                continue
            }

            let pathPointsBuffer = record.pathPointScreenBuffer(slot: frameContext.frameSlotIndex)
            roadPathScreenCompute.run(frameContext: frameContext,
                                      pointCount: record.pathPointCount,
                                      inputBuffer: pathInputsBuffer,
                                      tileSlotVisibleTileIndicesBuffer: record.visibleTileIndexBuffer,
                                      tileOriginDataBuffer: tileOriginDataBuffer,
                                      outputBuffer: pathPointsBuffer)

            let placementBuffer = record.placementBuffer(slot: frameContext.frameSlotIndex)
            let glyphScreenPointsBuffer = record.glyphScreenPointBuffer(slot: frameContext.frameSlotIndex)
            let collisionAabbBuffer = record.collisionAabbBuffer(slot: frameContext.frameSlotIndex)
            roadPlacementCalculator.run(commandBuffer: commandBuffer,
                                        pathPointsBuffer: pathPointsBuffer,
                                        pathRangesBuffer: pathRangesBuffer,
                                        anchorsBuffer: anchorsBuffer,
                                        glyphInputsBuffer: glyphInputsBuffer,
                                        placementsBuffer: placementBuffer,
                                        screenPointsBuffer: glyphScreenPointsBuffer,
                                        collisionInputsBuffer: collisionInputsBuffer,
                                        collisionAabbBuffer: collisionAabbBuffer,
                                        glyphCount: record.glyphCount)

            if index < staticBatches.count {
                let existingBatch = staticBatches[index]
                drawBatches.append(DrawRoadLabels(placementBuffer: placementBuffer,
                                                  glyphInputBuffer: glyphInputsBuffer,
                                                  runtimeMetaBuffer: existingBatch.runtimeMetaBuffer,
                                                  localGlyphVerticesBuffer: record.localGlyphVerticesBuffer,
                                                  glyphCount: record.glyphCount,
                                                  localGlyphVertexCount: record.localGlyphVertexCount,
                                                  labelStyle: record.labelStyle))
            }
        }

        frameContext.sharedState.roadLabelState.drawLabels = drawBatches
        frameContext.sharedState.roadLabelState.placementBuffer = drawBatches.first?.placementBuffer
        frameContext.sharedState.roadLabelState.glyphInputBuffer = drawBatches.first?.glyphInputBuffer
        frameContext.sharedState.roadLabelState.runtimeMetaBuffer = drawBatches.first?.runtimeMetaBuffer
        frameContext.sharedState.roadLabelState.glyphVerticesBuffer = drawBatches.first?.localGlyphVerticesBuffer
        frameContext.sharedState.roadLabelState.glyphVertexCount = drawBatches.first?.localGlyphVertexCount ?? 0
    }

    func encode(pass _: RenderPass, encoder _: MTLRenderCommandEncoder, frameContext _: FrameContext) {}

    func handleMemoryWarning() {
        reset()
    }

    func evict() {
        reset()
    }

    private func reset() {
        baseLabelCache.reset()
        roadLabelCache?.evict()
        presentationStateStore.reset()
        roadPresentationStateStore.reset()
        roadOrientationByInstanceKey.removeAll(keepingCapacity: false)
        roadDrawLabels.removeAll(keepingCapacity: false)
        sourceEntriesVersionTracker.invalidate()
        projectionVersionTracker.invalidate()
    }

    private func publishBaseLabelState(frameContext: FrameContext,
                                       hasActiveFadeAnimations: Bool,
                                       hasActiveVisibilityCycle: Bool) {
        frameContext.sharedState.baseLabelState.labelInputsCount = baseLabelCache.labelInputsCount
        frameContext.sharedState.baseLabelState.activeLabelSpanCount = baseLabelCache.activeLabelSpanCount
        frameContext.sharedState.baseLabelState.labelRuntimeMetaBuffer = baseLabelCache.labelRuntimeMetaBuffer(frameSlotIndex: frameContext.frameSlotIndex)
        frameContext.sharedState.baseLabelState.baseLabelsDrawBatches = baseLabelCache.baseLabelsDrawBatches
        frameContext.sharedState.baseLabelState.hasActiveFadeAnimations = hasActiveFadeAnimations
        frameContext.sharedState.baseLabelState.hasActiveVisibilityCycle = hasActiveVisibilityCycle
    }

    private func makeCpuScreenPoints(frameContext: FrameContext,
                                     tilePointSnapshot: TilePointToScreenPointSnapshot) -> [ScreenPointOutput] {
        guard baseLabelCache.activeLabelSpanCount > 0 else {
            return []
        }
        let projectionIndexState = frameContext.sharedState.tileProjectionIndexState
        return tilePointScreenProjector.project(snapshot: tilePointSnapshot,
                                                frameContext: frameContext,
                                                tileOriginData: projectionIndexState.tileOriginData)
    }

    private func makeCollisionFlagsBuffer(frameContext: FrameContext,
                                          collisionFlags: [UInt32],
                                          expectedCount: Int) -> MTLBuffer {
        let buffer = collisionFlagsBufferStore.ensureCapacity(slot: frameContext.frameSlotIndex,
                                                              count: max(1, expectedCount))
        upload(collisionFlags: collisionFlags, into: buffer, expectedCount: expectedCount)
        return buffer
    }

    private func refreshGpuTopology(trackedTilesChanged: Bool,
                                    projectionChanged: Bool) {
        if trackedTilesChanged {
            baseScreenCompute.uploadInputs(baseLabelCache.tilePointInputs)
        }
        if trackedTilesChanged || projectionChanged {
            baseScreenCompute.uploadTileSlotVisibleTileIndices(baseLabelCache.tilePointSnapshot.tileSlotVisibleTileIndices)
        }
    }

    private func resolveTileOriginDataBuffer(frameContext: FrameContext) -> MTLBuffer? {
        if let buffer = frameContext.sharedState.tileProjectionIndexState.tileOriginDataBuffer {
            return buffer
        }

        let tileOriginData = frameContext.sharedState.tileProjectionIndexState.tileOriginData
        guard tileOriginData.isEmpty == false else {
            return nil
        }

        let buffer = fallbackTileOriginDataBufferStore.ensureCapacity(slot: frameContext.frameSlotIndex,
                                                                      count: max(1, tileOriginData.count))
        tileOriginData.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!,
                                         byteCount: tileOriginData.count * MemoryLayout<FlatTileOriginData>.stride)
        }
        return buffer
    }

    private func reseedPublishedVisibilityState(baseVisibilityByKey: [UInt64: UInt32],
                                                roadVisibilityByKey: [UInt64: Bool]) {
        publishedBaseCollisionFlags = baseLabelCache.presentationInputs.map { input in
            guard input.isValid else {
                return UInt32(1)
            }
            return baseVisibilityByKey[input.labelKey] ?? 1
        }

        if let roadLabelCache {
            publishedRoadInstanceVisibility = roadLabelCache.instanceKeys.map { key in
                roadVisibilityByKey[key] ?? false
            }
        } else {
            publishedRoadInstanceVisibility = []
        }
    }

    private func makePublishedBaseVisibilityByKey() -> [UInt64: UInt32] {
        var visibilityByKey: [UInt64: UInt32] = [:]
        let inputs = baseLabelCache.presentationInputs
        let count = min(inputs.count, publishedBaseCollisionFlags.count)
        guard count > 0 else {
            return visibilityByKey
        }

        for index in 0..<count {
            let input = inputs[index]
            guard input.isValid else {
                continue
            }
            let flag = publishedBaseCollisionFlags[index]
            if let existing = visibilityByKey[input.labelKey] {
                visibilityByKey[input.labelKey] = min(existing, flag)
            } else {
                visibilityByKey[input.labelKey] = flag
            }
        }
        return visibilityByKey
    }

    private func makePublishedRoadVisibilityByKey() -> [UInt64: Bool] {
        guard let roadLabelCache else {
            return [:]
        }

        var visibilityByKey: [UInt64: Bool] = [:]
        let count = min(roadLabelCache.instanceKeys.count, publishedRoadInstanceVisibility.count)
        guard count > 0 else {
            return visibilityByKey
        }

        for index in 0..<count {
            let key = roadLabelCache.instanceKeys[index]
            let isVisible = publishedRoadInstanceVisibility[index]
            visibilityByKey[key] = (visibilityByKey[key] ?? false) || isVisible
        }
        return visibilityByKey
    }

    private func maybeStartVisibilityCycle(frameContext: FrameContext,
                                           forceRestart: Bool) {
        if forceRestart {
            visibilityCycle = makeVisibilityCycle(frameContext: frameContext)
            lastVisibilityCycleStartTime = frameContext.time
            return
        }

        guard visibilityCycle == nil else {
            return
        }

        let cameraChanged = latestCameraFingerprint != publishedVisibilityCameraFingerprint
        let cadenceElapsed = frameContext.time - lastVisibilityCycleStartTime >= visibilityRefreshInterval
        guard cameraChanged, cadenceElapsed else {
            return
        }

        visibilityCycle = makeVisibilityCycle(frameContext: frameContext)
        lastVisibilityCycleStartTime = frameContext.time
    }

    private func advanceVisibilityCycleIfNeeded(frameContext: FrameContext) {
        guard var cycle = visibilityCycle else {
            return
        }

        cycle.processNextGroups(maxGroupCount: collisionGroupBudgetPerFrame)
        if cycle.isComplete == false {
            visibilityCycle = cycle
            return
        }

        let shouldPublish = cycle.topologyGeneration == visibilityTopologyGeneration &&
            cycle.cameraFingerprint == latestCameraFingerprint
        if shouldPublish {
            publishedBaseCollisionFlags = cycle.baseCollisionFlags
            publishedRoadInstanceVisibility = cycle.roadInstanceVisibility
            publishedVisibilityCameraFingerprint = cycle.cameraFingerprint
        }
        visibilityCycle = nil
    }

    private func makeVisibilityCycle(frameContext: FrameContext) -> VisibilityCycle {
        let tilePointSnapshot = baseLabelCache.tilePointSnapshot
        let screenPoints = makeCpuScreenPoints(frameContext: frameContext,
                                               tilePointSnapshot: tilePointSnapshot)
        var baseCollisionCandidates = baseLabelCache.labelCollisionAABBInputs
        let baseCount = min(screenPoints.count, baseCollisionCandidates.count)
        if baseCount > 0 {
            for index in 0..<baseCount {
                baseCollisionCandidates[index].position = screenPoints[index].position
                baseCollisionCandidates[index].groupId = 0
                if screenPoints[index].visible == 0 || screenPoints[index].visibilityAlpha < 0.999 {
                    baseCollisionCandidates[index].isEnabled = false
                }
            }
        }

        let roadPreparation = prepareRoadInstances(frameContext: frameContext,
                                                   projectionIndexState: frameContext.sharedState.tileProjectionIndexState)
        let collisionGroups = makeCollisionGroups(baseCandidates: baseCollisionCandidates,
                                                  roadInstances: roadPreparation.instances)
        return VisibilityCycle(topologyGeneration: visibilityTopologyGeneration,
                               cameraFingerprint: latestCameraFingerprint,
                               viewportSize: SIMD2<Float>(Float(frameContext.drawSize.width),
                                                          Float(frameContext.drawSize.height)),
                               baseCount: baseLabelCache.activeLabelSpanCount,
                               roadCount: roadLabelCache?.instanceKeys.count ?? 0,
                               groups: collisionGroups,
                               cellSizePx: collisionGridCellSizePx)
    }

    private func makeCollisionGroups(baseCandidates: [ScreenCollisionCandidate],
                                     roadInstances: [RoadPreparedInstance]) -> [VisibilityCollisionGroup] {
        var groups: [VisibilityCollisionGroup] = []
        groups.reserveCapacity(baseCandidates.count + roadInstances.count)

        for index in baseCandidates.indices {
            let candidate = baseCandidates[index]
            groups.append(VisibilityCollisionGroup(target: .base(index),
                                                  members: [candidate],
                                                  priority: candidate.priority,
                                                  secondaryPriority: candidate.secondaryPriority))
        }

        for instance in roadInstances {
            guard let firstCandidate = instance.collisionCandidates.first else {
                continue
            }
            groups.append(VisibilityCollisionGroup(target: .road(instance.targetIndex),
                                                  members: instance.collisionCandidates,
                                                  priority: firstCandidate.priority,
                                                  secondaryPriority: firstCandidate.secondaryPriority))
        }

        return groups.sorted(by: VisibilityCollisionGroup.sortForCollisionOrder)
    }

    private func makeVisibilityCameraFingerprint(frameContext: FrameContext) -> Int {
        var hasher = Hasher()
        let cameraState = frameContext.mapCameraState
        hasher.combine(cameraState.centerWorldMercator.x.bitPattern)
        hasher.combine(cameraState.centerWorldMercator.y.bitPattern)
        hasher.combine(cameraState.zoom.bitPattern)
        hasher.combine(cameraState.bearing.bitPattern)
        hasher.combine(cameraState.pitch.bitPattern)
        hasher.combine(Int(frameContext.drawSize.width.rounded()))
        hasher.combine(Int(frameContext.drawSize.height.rounded()))
        hasher.combine(frameContext.renderBackendMode == .flat)
        hasher.combine(frameContext.screenSpaceProjectionMode == .flat)
        return hasher.finalize()
    }

    private func prepareRoadInstances(frameContext: FrameContext,
                                      projectionIndexState: TileProjectionIndexState) -> RoadPreparation {
        guard let roadLabelCache,
              frameContext.renderBackendMode == .flat,
              roadLabelCache.orderedTileRecords.isEmpty == false else {
            return RoadPreparation(instances: [])
        }

        var instances: [RoadPreparedInstance] = []
        instances.reserveCapacity(roadLabelCache.instanceKeys.count)

        for record in roadLabelCache.orderedTileRecords {
            let localVisibleTileIndices = [record.visibleTileIndex]
            for entry in record.entries {
                let snapshot = TilePointToScreenPointSnapshot(pointInputs: entry.pointInputs,
                                                              tileSlotVisibleTileIndices: localVisibleTileIndices)
                let screenPoints = tilePointScreenProjector.project(snapshot: snapshot,
                                                                    frameContext: frameContext,
                                                                    tileOriginData: projectionIndexState.tileOriginData)
                guard let screenPath = makeScreenPath(points: screenPoints) else {
                    continue
                }

                guard screenPath.totalLength >= entry.labelSize.x else {
                    continue
                }

                for anchor in entry.anchors {
                    guard let instance = makeRoadPreparedInstance(record: record,
                                                                  entry: entry,
                                                                  anchor: anchor,
                                                                  screenPath: screenPath) else {
                        continue
                    }
                    instances.append(instance)
                }
            }
        }

        return RoadPreparation(instances: instances)
    }

    private func makeRoadPreparedInstance(record: RoadLabelTileRecord,
                                          entry: RoadLabelEntry,
                                          anchor: RoadLabelAnchor,
                                          screenPath: RoadScreenPath) -> RoadPreparedInstance? {
        guard let centerDistance = makeAnchorCenterDistance(anchor: anchor,
                                                            screenPath: screenPath) else {
            return nil
        }
        let instanceKey = makeRoadInstanceKey(entryKey: entry.entryKey,
                                              anchorOrdinal: anchor.anchorOrdinal)
        guard let targetIndex = record.instanceKeys.firstIndex(of: instanceKey).map({ record.instanceStart + $0 }) else {
            return nil
        }
        let orientation = chooseOrientation(entry: entry,
                                            centerDistance: centerDistance,
                                            screenPath: screenPath,
                                            previousReverse: roadOrientationByInstanceKey[instanceKey])
        guard let orientation else {
            return nil
        }
        roadOrientationByInstanceKey[instanceKey] = orientation.reverse

        var placements: [RoadGlyphPlacementOutput] = []
        placements.reserveCapacity(entry.glyphBounds.count)
        var collisionCandidates: [ScreenCollisionCandidate] = []
        collisionCandidates.reserveCapacity(entry.glyphBounds.count)
        var glyphCenters: [Float] = []
        glyphCenters.reserveCapacity(entry.glyphBounds.count)
        let secondaryPriority = entry.sourcePriority * 1024 + Int(anchor.anchorOrdinal)

        for glyphBounds in entry.glyphBounds {
            let glyphCenter = (glyphBounds.x + glyphBounds.y) * 0.5
            let localOffset = glyphCenter - entry.labelSize.x * 0.5
            let targetDistance = orientation.reverse ? (centerDistance - localOffset) : (centerDistance + localOffset)
            guard let sample = sampleScreenPath(screenPath, distance: targetDistance, reverse: orientation.reverse) else {
                return nil
            }

            let glyphHalfSize = SIMD2<Float>((glyphBounds.y - glyphBounds.x) * 0.5,
                                             (glyphBounds.w - glyphBounds.z) * 0.5)
            placements.append(RoadGlyphPlacementOutput(position: sample.position,
                                                       angle: sample.angle,
                                                       visible: 1))
            collisionCandidates.append(ScreenCollisionCandidate(position: sample.position,
                                                                halfSize: glyphHalfSize,
                                                                priority: roadPriorityBase,
                                                                secondaryPriority: secondaryPriority,
                                                                groupId: instanceKey,
                                                                isEnabled: true))
            glyphCenters.append(glyphCenter)
        }

        return RoadPreparedInstance(instanceKey: instanceKey,
                                    targetIndex: targetIndex,
                                    collisionCandidates: collisionCandidates,
                                    placements: placements)
    }

    private func chooseOrientation(entry: RoadLabelEntry,
                                   centerDistance: Float,
                                   screenPath: RoadScreenPath,
                                   previousReverse: Bool?) -> RoadOrientationChoice? {
        let forward = evaluateOrientation(reverse: false,
                                          entry: entry,
                                          centerDistance: centerDistance,
                                          screenPath: screenPath)
        let reverse = evaluateOrientation(reverse: true,
                                          entry: entry,
                                          centerDistance: centerDistance,
                                          screenPath: screenPath)

        switch (forward, reverse) {
        case let (.some(lhs), .some(rhs)):
            let difference = abs(lhs.score - rhs.score)
            if difference < orientationScoreEpsilon,
               let previousReverse {
                return previousReverse ? rhs : lhs
            }
            return lhs.score >= rhs.score ? lhs : rhs
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    private func evaluateOrientation(reverse: Bool,
                                     entry: RoadLabelEntry,
                                     centerDistance: Float,
                                     screenPath: RoadScreenPath) -> RoadOrientationChoice? {
        guard entry.glyphBounds.isEmpty == false else {
            return nil
        }

        var angles: [Float] = []
        angles.reserveCapacity(entry.glyphBounds.count)
        var tangentXSum: Float = 0

        for glyphBounds in entry.glyphBounds {
            let glyphCenter = (glyphBounds.x + glyphBounds.y) * 0.5
            let localOffset = glyphCenter - entry.labelSize.x * 0.5
            let targetDistance = reverse ? (centerDistance - localOffset) : (centerDistance + localOffset)
            guard let sample = sampleScreenPath(screenPath, distance: targetDistance, reverse: reverse) else {
                return nil
            }
            angles.append(sample.angle)
            tangentXSum += sample.tangent.x
        }

        if angles.count > 1 {
            for index in 1..<angles.count {
                let delta = normalizedAngleDelta(lhs: angles[index - 1], rhs: angles[index])
                if abs(delta) > maxGlyphTurnRadians {
                    return nil
                }
            }
        }

        return RoadOrientationChoice(reverse: reverse,
                                     score: tangentXSum / Float(max(1, angles.count)))
    }

    private func buildRoadLabelState(frameContext: FrameContext,
                                     roadVisibility: [Bool]) -> RoadLabelState {
        guard let roadLabelCache,
              frameContext.renderBackendMode == .flat,
              roadLabelCache.instanceKeys.isEmpty == false else {
            return .empty
        }

        var presentationInputs: [BaseLabelPresentationInput] = []
        presentationInputs.reserveCapacity(roadLabelCache.instanceKeys.count)
        var targetVisibility: [Bool] = []
        targetVisibility.reserveCapacity(roadLabelCache.instanceKeys.count)

        for index in roadLabelCache.instanceKeys.indices {
            let instanceKey = roadLabelCache.instanceKeys[index]
            let isRetained = roadLabelCache.instanceRetainedFlags[index]
            presentationInputs.append(BaseLabelPresentationInput(labelKey: instanceKey,
                                                                 duplicate: 0,
                                                                 isRetained: isRetained,
                                                                 isValid: true))
            targetVisibility.append(index < roadVisibility.count ? roadVisibility[index] : false)
        }

        let fadeResolution = roadPresentationStateStore.resolveAlphas(inputs: presentationInputs,
                                                                      targetVisibility: targetVisibility,
                                                                      time: frameContext.time,
                                                                      frameIndex: frameContext.frameIndex,
                                                                      fadeInSeconds: fadeInSeconds,
                                                                      fadeOutSeconds: fadeOutSeconds)

        let frameSlotIndex = frameContext.frameSlotIndex
        var aggregatedRuntimeMeta: [LabelRuntimeMeta] = []
        aggregatedRuntimeMeta.reserveCapacity(roadLabelCache.instanceKeys.count)
        var drawBatches: [DrawRoadLabels] = []
        drawBatches.reserveCapacity(roadLabelCache.orderedTileRecords.count)
        var totalGlyphCount = 0

        for record in roadLabelCache.orderedTileRecords {
            let start = record.instanceStart
            let end = start + record.instanceKeys.count
            var runtimeMeta: [LabelRuntimeMeta] = []
            runtimeMeta.reserveCapacity(record.instanceKeys.count)
            for index in start..<end {
                let alpha = index < fadeResolution.fadeAlphas.count ? fadeResolution.fadeAlphas[index] : 0
                let meta = LabelRuntimeMeta(duplicate: 0,
                                            isRetained: roadLabelCache.instanceRetainedFlags[index],
                                            visibleTileIndex: 0,
                                            fadeAlpha: alpha,
                                            labelSizePx: roadLabelCache.instanceLabelSizes[index])
                runtimeMeta.append(meta)
                aggregatedRuntimeMeta.append(meta)
            }
            let runtimeMetaBuffer = record.runtimeMetaBuffer(slot: frameSlotIndex, meta: runtimeMeta)
            drawBatches.append(DrawRoadLabels(placementBuffer: nil,
                                              glyphInputBuffer: record.glyphInputsBuffer,
                                              runtimeMetaBuffer: runtimeMetaBuffer,
                                              localGlyphVerticesBuffer: record.localGlyphVerticesBuffer,
                                              glyphCount: record.glyphCount,
                                              localGlyphVertexCount: record.localGlyphVertexCount,
                                              labelStyle: record.labelStyle))
            totalGlyphCount += record.glyphCount
        }

        let hasVisibleOrAnimatingRoadLabels = fadeResolution.hasActiveAnimations ||
            aggregatedRuntimeMeta.contains(where: { $0.fadeAlpha > 0.0001 })
        guard hasVisibleOrAnimatingRoadLabels else {
            roadDrawLabels = []
            return .empty
        }

        let runtimeMetaBuffer = roadRuntimeMetaBufferStore.ensureCapacity(slot: frameSlotIndex,
                                                                          count: max(1, aggregatedRuntimeMeta.count))
        upload(values: aggregatedRuntimeMeta, into: runtimeMetaBuffer)
        roadDrawLabels = drawBatches
        return RoadLabelState(instanceCount: roadLabelCache.instanceKeys.count,
                              glyphCount: totalGlyphCount,
                              runtimeMetaBuffer: runtimeMetaBuffer,
                              placementBuffer: nil,
                              glyphInputBuffer: drawBatches.first?.glyphInputBuffer,
                              glyphVerticesBuffer: drawBatches.first?.localGlyphVerticesBuffer,
                              glyphVertexCount: drawBatches.first?.localGlyphVertexCount ?? 0,
                              drawLabels: drawBatches,
                              hasActiveFadeAnimations: fadeResolution.hasActiveAnimations)
    }

    private func upload<T>(values: [T], into buffer: MTLBuffer) {
        guard values.isEmpty == false else {
            return
        }
        values.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!,
                                         byteCount: values.count * MemoryLayout<T>.stride)
        }
    }

    private func copy<T>(values: [T], into buffer: MTLBuffer) {
        guard values.isEmpty == false else {
            return
        }
        values.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!,
                                         byteCount: values.count * MemoryLayout<T>.stride)
        }
    }

    private func makeAnchorCenterDistance(anchor: RoadLabelAnchor,
                                          screenPath: RoadScreenPath) -> Float? {
        guard screenPath.totalLength > 0,
              screenPath.points.count > 1 else {
            return nil
        }
        let segmentIndex = min(Int(anchor.segmentIndex), screenPath.points.count - 2)
        let startDistance = screenPath.cumulativeLengths[segmentIndex]
        let endDistance = screenPath.cumulativeLengths[segmentIndex + 1]
        let t = simd_clamp(anchor.t, 0.0, 1.0)
        return startDistance + (endDistance - startDistance) * t
    }

    private func makeScreenPath(points: [ScreenPointOutput]) -> RoadScreenPath? {
        guard points.count > 1 else {
            return nil
        }

        var pathPoints: [SIMD2<Float>] = []
        pathPoints.reserveCapacity(points.count)
        for point in points {
            guard point.visible != 0 else {
                return nil
            }
            pathPoints.append(point.position)
        }

        guard pathPoints.count > 1 else {
            return nil
        }

        var cumulativeLengths: [Float] = [0]
        cumulativeLengths.reserveCapacity(pathPoints.count)
        var total: Float = 0
        for index in 1..<pathPoints.count {
            total += simd_length(pathPoints[index] - pathPoints[index - 1])
            cumulativeLengths.append(total)
        }
        guard total > 0 else {
            return nil
        }

        return RoadScreenPath(points: pathPoints,
                              cumulativeLengths: cumulativeLengths,
                              totalLength: total)
    }

    private func sampleScreenPath(_ screenPath: RoadScreenPath,
                                  distance: Float,
                                  reverse: Bool) -> RoadPathSample? {
        guard distance >= 0,
              distance <= screenPath.totalLength else {
            return nil
        }

        var segmentIndex = 0
        while segmentIndex < screenPath.cumulativeLengths.count - 1,
              screenPath.cumulativeLengths[segmentIndex + 1] < distance {
            segmentIndex += 1
        }

        let startDistance = screenPath.cumulativeLengths[segmentIndex]
        let endDistance = screenPath.cumulativeLengths[segmentIndex + 1]
        let startPoint = screenPath.points[segmentIndex]
        let endPoint = screenPath.points[segmentIndex + 1]
        let segmentVector = endPoint - startPoint
        let segmentLength = max(endDistance - startDistance, 1e-6)
        let t = simd_clamp((distance - startDistance) / segmentLength, 0, 1)
        let position = simd_mix(startPoint, endPoint, SIMD2<Float>(repeating: t))
        var tangent = simd_normalize(segmentVector)
        if reverse {
            tangent *= -1
        }
        let angle = atan2(tangent.y, tangent.x)
        return RoadPathSample(position: position,
                              tangent: tangent,
                              angle: angle)
    }

    private func normalizedAngleDelta(lhs: Float, rhs: Float) -> Float {
        var delta = rhs - lhs
        while delta > .pi {
            delta -= 2 * .pi
        }
        while delta < -.pi {
            delta += 2 * .pi
        }
        return delta
    }

    private func upload(screenPoints: [ScreenPointOutput],
                        into buffer: MTLBuffer,
                        expectedCount: Int) {
        if screenPoints.isEmpty {
            writeDefaultScreenPoint(into: buffer)
            return
        }

        screenPoints.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!,
                                         byteCount: screenPoints.count * MemoryLayout<ScreenPointOutput>.stride)
        }

        let missingCount = max(0, expectedCount - screenPoints.count)
        if missingCount > 0 {
            let byteOffset = screenPoints.count * MemoryLayout<ScreenPointOutput>.stride
            buffer.contents().advanced(by: byteOffset).initializeMemory(as: UInt8.self,
                                                                        repeating: 0,
                                                                        count: missingCount * MemoryLayout<ScreenPointOutput>.stride)
        }
    }

    private func upload(collisionFlags: [UInt32],
                        into buffer: MTLBuffer,
                        expectedCount: Int) {
        if collisionFlags.isEmpty {
            buffer.contents().storeBytes(of: UInt32(0), as: UInt32.self)
            return
        }

        collisionFlags.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!,
                                         byteCount: collisionFlags.count * MemoryLayout<UInt32>.stride)
        }

        let missingCount = max(0, expectedCount - collisionFlags.count)
        if missingCount > 0 {
            let byteOffset = collisionFlags.count * MemoryLayout<UInt32>.stride
            buffer.contents().advanced(by: byteOffset).initializeMemory(as: UInt8.self,
                                                                        repeating: 0,
                                                                        count: missingCount * MemoryLayout<UInt32>.stride)
        }
    }

    private func writeDefaultScreenPoint(into buffer: MTLBuffer) {
        var point = ScreenPointOutput(position: .zero, depth: 0, visible: 0, visibilityAlpha: 0.0)
        withUnsafeBytes(of: &point) { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!,
                                         byteCount: MemoryLayout<ScreenPointOutput>.stride)
        }
    }

    private func makeRoadInstanceKey(entryKey: UInt64,
                                     anchorOrdinal: UInt32) -> UInt64 {
        var hash = entryKey
        hash ^= UInt64(anchorOrdinal) &* 1469598103934665603
        return hash
    }
}

private struct RoadPreparation {
    let instances: [RoadPreparedInstance]
}

private enum VisibilityCollisionTarget {
    case base(Int)
    case road(Int)
}

private struct VisibilityCollisionGroup {
    let target: VisibilityCollisionTarget
    let members: [ScreenCollisionCandidate]
    let priority: Int
    let secondaryPriority: Int

    static func sortForCollisionOrder(lhs: VisibilityCollisionGroup,
                                      rhs: VisibilityCollisionGroup) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        if lhs.secondaryPriority != rhs.secondaryPriority {
            return lhs.secondaryPriority < rhs.secondaryPriority
        }
        return lhs.stableOrderKey < rhs.stableOrderKey
    }

    private var stableOrderKey: UInt64 {
        switch target {
        case let .base(index):
            return UInt64(index)
        case let .road(index):
            return UInt64(index) | (1 << 63)
        }
    }
}

private struct VisibilityCycle {
    let topologyGeneration: UInt64
    let cameraFingerprint: Int
    private let groups: [VisibilityCollisionGroup]
    private let gridWidth: Int
    private let gridHeight: Int
    private let cellSizePx: Float

    private(set) var cursor: Int = 0
    private(set) var baseCollisionFlags: [UInt32]
    private(set) var roadInstanceVisibility: [Bool]
    private var gridBuckets: [[VisibilityPlacedCandidate]]

    init(topologyGeneration: UInt64,
         cameraFingerprint: Int,
         viewportSize: SIMD2<Float>,
         baseCount: Int,
         roadCount: Int,
         groups: [VisibilityCollisionGroup],
         cellSizePx: Float) {
        self.topologyGeneration = topologyGeneration
        self.cameraFingerprint = cameraFingerprint
        self.groups = groups
        self.cellSizePx = cellSizePx
        self.gridWidth = max(1, Int(ceil(max(1.0, viewportSize.x) / cellSizePx)))
        self.gridHeight = max(1, Int(ceil(max(1.0, viewportSize.y) / cellSizePx)))
        self.baseCollisionFlags = Array(repeating: 0, count: baseCount)
        self.roadInstanceVisibility = Array(repeating: false, count: roadCount)
        self.gridBuckets = Array(repeating: [], count: max(1, self.gridWidth * self.gridHeight))
    }

    var isComplete: Bool {
        cursor >= groups.count
    }

    mutating func processNextGroups(maxGroupCount: Int) {
        guard maxGroupCount > 0, isComplete == false else {
            return
        }

        let end = min(groups.count, cursor + maxGroupCount)
        while cursor < end {
            processGroup(groups[cursor])
            cursor += 1
        }
    }

    private mutating func processGroup(_ group: VisibilityCollisionGroup) {
        var covered: [(candidate: VisibilityPlacedCandidate, cells: CoveredCellRange)] = []
        covered.reserveCapacity(group.members.count)
        var hasCollision = false

        for member in group.members {
            guard member.isEnabled,
                  let cells = makeCoveredCellRange(for: member) else {
                continue
            }
            let placed = VisibilityPlacedCandidate(position: member.position,
                                                   halfSize: member.halfSize,
                                                   groupId: member.groupId)
            if intersectsExisting(candidate: placed, cells: cells) {
                hasCollision = true
                break
            }
            covered.append((placed, cells))
        }

        if hasCollision {
            applyRejected(group.target)
            return
        }

        for item in covered {
            insert(item.candidate, cells: item.cells)
        }
        applyAccepted(group.target)
    }

    private mutating func applyAccepted(_ target: VisibilityCollisionTarget) {
        switch target {
        case let .base(index):
            guard index < baseCollisionFlags.count else { return }
            baseCollisionFlags[index] = 0
        case let .road(index):
            guard index < roadInstanceVisibility.count else { return }
            roadInstanceVisibility[index] = true
        }
    }

    private mutating func applyRejected(_ target: VisibilityCollisionTarget) {
        switch target {
        case let .base(index):
            guard index < baseCollisionFlags.count else { return }
            baseCollisionFlags[index] = 1
        case let .road(index):
            guard index < roadInstanceVisibility.count else { return }
            roadInstanceVisibility[index] = false
        }
    }

    private func intersectsExisting(candidate: VisibilityPlacedCandidate,
                                    cells: CoveredCellRange) -> Bool {
        for cellY in cells.minY...cells.maxY {
            for cellX in cells.minX...cells.maxX {
                let bucketIndex = cellY * gridWidth + cellX
                for other in gridBuckets[bucketIndex] {
                    if candidate.groupId != 0,
                       candidate.groupId == other.groupId {
                        continue
                    }
                    let delta = simd_abs(candidate.position - other.position)
                    let overlap = candidate.halfSize + other.halfSize
                    if delta.x < overlap.x && delta.y < overlap.y {
                        return true
                    }
                }
            }
        }
        return false
    }

    private mutating func insert(_ candidate: VisibilityPlacedCandidate,
                                 cells: CoveredCellRange) {
        for cellY in cells.minY...cells.maxY {
            for cellX in cells.minX...cells.maxX {
                let bucketIndex = cellY * gridWidth + cellX
                gridBuckets[bucketIndex].append(candidate)
            }
        }
    }

    private func makeCoveredCellRange(for candidate: ScreenCollisionCandidate) -> CoveredCellRange? {
        let viewportSize = SIMD2<Float>(Float(gridWidth) * cellSizePx, Float(gridHeight) * cellSizePx)
        let minX = candidate.position.x - candidate.halfSize.x
        let maxX = candidate.position.x + candidate.halfSize.x
        let minY = candidate.position.y - candidate.halfSize.y
        let maxY = candidate.position.y + candidate.halfSize.y

        if maxX < 0 || maxY < 0 || minX > viewportSize.x || minY > viewportSize.y {
            return nil
        }

        let clampedMinX = max(0.0, minX)
        let clampedMaxX = min(viewportSize.x, maxX)
        let clampedMinY = max(0.0, minY)
        let clampedMaxY = min(viewportSize.y, maxY)

        let startCellX = min(max(Int(floor(clampedMinX / cellSizePx)), 0), gridWidth - 1)
        let endCellX = min(max(Int(floor(clampedMaxX / cellSizePx)), 0), gridWidth - 1)
        let startCellY = min(max(Int(floor(clampedMinY / cellSizePx)), 0), gridHeight - 1)
        let endCellY = min(max(Int(floor(clampedMaxY / cellSizePx)), 0), gridHeight - 1)

        return CoveredCellRange(minX: startCellX,
                                maxX: endCellX,
                                minY: startCellY,
                                maxY: endCellY)
    }
}

private struct VisibilityPlacedCandidate {
    let position: SIMD2<Float>
    let halfSize: SIMD2<Float>
    let groupId: UInt64
}

private struct CoveredCellRange {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int
}

private struct RoadPreparedInstance {
    let instanceKey: UInt64
    let targetIndex: Int
    let collisionCandidates: [ScreenCollisionCandidate]
    let placements: [RoadGlyphPlacementOutput]
}

private struct RoadScreenPath {
    let points: [SIMD2<Float>]
    let cumulativeLengths: [Float]
    let totalLength: Float
}

private struct RoadPathSample {
    let position: SIMD2<Float>
    let tangent: SIMD2<Float>
    let angle: Float
}

private struct RoadOrientationChoice {
    let reverse: Bool
    let score: Float
}
