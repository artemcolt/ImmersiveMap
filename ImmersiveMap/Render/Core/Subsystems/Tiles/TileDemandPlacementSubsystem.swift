// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  TileDemandPlacementSubsystem.swift
//  ImmersiveMap
//

import Foundation
import Metal
import simd

final class TileDemandPlacementSubsystem: RenderSubsystem {
    let name: String = "TileDemandPlacement"
    
    private let tileRenderStore: TileRenderStore
    private let tileTraceRecorder: TileTraceRecorder
    private let visibleTilesPreprocessor: VisibleTilesPreprocessor

    private var previousZoom: Int
    private var preprocessedVisibleTilesHashTracker = StagedHashChangeTracker()
    private var placeTilesContext: PlaceTilesContext = .empty
    private var globeTexturePlaceTilesContext: GlobeTexturePlaceTilesContext = .empty
    private var placementVersion: UInt64 = 0

    init(tileRenderStore: TileRenderStore,
         tileTraceRecorder: TileTraceRecorder,
         visibleTilesPreprocessor: VisibleTilesPreprocessor = VisibleTilesPreprocessor(),
         initialZoom: Int) {
        self.tileRenderStore = tileRenderStore
        self.tileTraceRecorder = tileTraceRecorder
        self.visibleTilesPreprocessor = visibleTilesPreprocessor
        self.previousZoom = initialZoom
    }

    func update(frameContext: FrameContext) {
        // Tile culling stage: resolves current map-space center and
        // computes which tiles are visible for the active view mode.
        let visibleContent = frameContext.visibleContent
        let center = visibleContent.center
        let visibleTiles = visibleContent.visibleTiles
        let tileZoomLevel = visibleContent.tileZoomLevel
        
        // Visible-tiles post-processing:
        // shortens the raw visible list and substitutes distant tiles
        // with coarser parents to reduce load/placement pressure.
        let preprocessedVisibleTiles = visibleTilesPreprocessor.preprocess(visibleTiles: visibleTiles,
                                                                           center: center,
                                                                           renderSurfaceMode: frameContext.renderSurfaceMode)
        // `VisibleTile` includes `loop`, so flat-mode wrapped copies can produce
        // multiple placement targets that share the same content tile (`Tile`).
        // Deduplicate before storage request to avoid repeated cache lookup/request
        // for identical source bytes.
        let demandedSourceTiles = TileDemandSourcePlanner.makeDemandedSourceTiles(targets: preprocessedVisibleTiles,
                                                                                  parentFallbackDepth: 2)
        // Returns source-tile availability map for GPU rendering:
        // value contains Metal-ready tile buffers, or `nil` while still loading.
        let tileRequestResult = tileRenderStore.requestTiles(demandedSourceTiles,
                                                             frameIndex: frameContext.frameIndex)
        let readyTilesBySource = tileRequestResult.readyTilesBySource

        var hashBuilder = Hasher()
        hashBuilder.combine(PreprocessedVisibleTilesHasher.computePreprocessedVisibleTilesHash(
            preprocessedVisibleTiles: preprocessedVisibleTiles,
            demandedSourceTiles: demandedSourceTiles,
            readyTilesBySource: readyTilesBySource
        ))
        let preprocessedVisibleTilesHash = hashBuilder.finalize()

        let placementChanged = preprocessedVisibleTilesHashTracker.stage(preprocessedVisibleTilesHash)
        if placementChanged {
            placeTilesContext = TilePlacementPlanner.buildPlacements(targets: preprocessedVisibleTiles,
                                                                     readyTilesBySource: readyTilesBySource,
                                                                     zoom: tileZoomLevel,
                                                                     previousZoom: previousZoom,
                                                                     previousContext: placeTilesContext)
            globeTexturePlaceTilesContext = GlobeTexturePlacementPlanner.buildPlacements(baseTargets: preprocessedVisibleTiles,
                                                                                         readyTilesBySource: readyTilesBySource,
                                                                                         baseZoom: tileZoomLevel,
                                                                                         previousBaseZoom: previousZoom,
                                                                                         previousContext: globeTexturePlaceTilesContext)
            previousZoom = tileZoomLevel
            placementVersion &+= 1
            preprocessedVisibleTilesHashTracker.commitPending()
        }

        let visibleTilesCount = visibleTiles.count
        let readyTilesCount = tileRequestResult.readyTilesCount
        let requestedTilesCount = tileRequestResult.requestedTilesCount
        let renderedTilesCount = placeTilesContext.tilePlacements.count
        let lodSummary = summarizeLOD(placeTilesContext.tilePlacements)
        tileTraceRecorder.record(.tileDemandUpdate(frameIndex: frameContext.frameIndex,
                                                   visible: visibleTilesCount,
                                                   preprocessed: preprocessedVisibleTiles.count,
                                                   demanded: demandedSourceTiles.count,
                                                   ready: readyTilesCount,
                                                   requested: requestedTilesCount,
                                                   rendered: renderedTilesCount,
                                                   placementChanged: placementChanged,
                                                   placementVersion: placementVersion,
                                                   surface: frameContext.renderSurfaceMode == .spherical ? "globe" : "flat",
                                                   lodExact: lodSummary.exact,
                                                   lodCoarse: lodSummary.coarse,
                                                   lodRetained: lodSummary.retained))

        frameContext.sharedState.tilePlacementState = TilePlacementState(
            placeTilesContext: placeTilesContext,
            globeTexturePlaceTilesContext: globeTexturePlaceTilesContext,
            placementVersion: placementVersion,
            visibleTilesCount: visibleTilesCount,
            readyTilesCount: readyTilesCount,
            requestedTilesCount: requestedTilesCount,
            renderedTilesCount: renderedTilesCount
        )
        frameContext.sharedState.placeTileTrackingState = PlaceTileTrackingState(placeTiles: placeTilesContext.tilePlacements)

        frameContext.services.diagnostics.setCounter(.visibleTiles, value: visibleTilesCount)
        frameContext.services.diagnostics.setCounter(.readyTiles, value: readyTilesCount)
        frameContext.services.diagnostics.setCounter(.requestedTiles, value: requestedTilesCount)
        frameContext.services.diagnostics.setCounter(.renderedTiles, value: renderedTilesCount)
    }

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer _: RenderLayer, encoder _: MTLRenderCommandEncoder, frameContext _: FrameContext) {}

    func handleMemoryWarning() {
        tileRenderStore.handleMemoryWarning()
        placeTilesContext = .empty
        globeTexturePlaceTilesContext = .empty
        preprocessedVisibleTilesHashTracker.invalidate()
        placementVersion &+= 1
    }

    func evict() {
        tileRenderStore.evict()
        placeTilesContext = .empty
        globeTexturePlaceTilesContext = .empty
        preprocessedVisibleTilesHashTracker.invalidate()
        placementVersion &+= 1
    }

    private func summarizeLOD(_ placements: [PlaceTile]) -> (exact: Int, coarse: Int, retained: Int) {
        var exact = 0
        var coarse = 0
        var retained = 0
        for placement in placements {
            switch placement.lodKind {
            case .exact:
                exact += 1
            case .coarseSubstitute:
                coarse += 1
            case .retainedReplacement:
                retained += 1
            }
        }
        return (exact: exact, coarse: coarse, retained: retained)
    }
}
