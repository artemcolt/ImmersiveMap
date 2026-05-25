//
//  TileDemandPlacementSubsystem.swift
//  ImmersiveMapFramework
//

import Foundation
import Metal
import simd

final class TileDemandPlacementSubsystem: RenderSubsystem {
    let name: String = "TileDemandPlacement"
    
    private let tileRenderStore: TileRenderStore
    private let visibleTilesPreprocessor: VisibleTilesPreprocessor

    private var previousZoom: Int
    private var preprocessedVisibleTilesHashTracker = StagedHashChangeTracker()
    private var placeTilesContext: PlaceTilesContext = .empty
    private var placementVersion: UInt64 = 0

    init(tileRenderStore: TileRenderStore,
         visibleTilesPreprocessor: VisibleTilesPreprocessor = VisibleTilesPreprocessor(),
         initialZoom: Int) {
        self.tileRenderStore = tileRenderStore
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
                                                                           visibilityMode: frameContext.resolvedPresentation.visibilityMode)
        // `VisibleTile` includes `loop`, so flat-mode wrapped copies can produce
        // multiple placement targets that share the same content tile (`Tile`).
        // Deduplicate before storage request to avoid repeated cache lookup/request
        // for identical source bytes.
        let demandedSourceTiles = deduplicateSourceTiles(preprocessedVisibleTiles)
        // Returns source-tile availability map for GPU rendering:
        // value contains Metal-ready tile buffers, or `nil` while still loading.
        let tileRequestResult = tileRenderStore.requestTiles(demandedSourceTiles)
        let readyTilesBySource = tileRequestResult.readyTilesBySource

        let preprocessedVisibleTilesHash = PreprocessedVisibleTilesHasher.computePreprocessedVisibleTilesHash(
            preprocessedVisibleTiles: preprocessedVisibleTiles,
            readyTilesBySource: readyTilesBySource
        )

        if preprocessedVisibleTilesHashTracker.stage(preprocessedVisibleTilesHash) {
            placeTilesContext = TilePlacementPlanner.buildPlacements(targets: preprocessedVisibleTiles,
                                                                     readyTilesBySource: readyTilesBySource,
                                                                     zoom: tileZoomLevel,
                                                                     previousZoom: previousZoom,
                                                                     previousContext: placeTilesContext)
            previousZoom = tileZoomLevel
            placementVersion &+= 1
            preprocessedVisibleTilesHashTracker.commitPending()
        }

        let visibleTilesCount = visibleTiles.count
        let readyTilesCount = tileRequestResult.readyTilesCount
        let requestedTilesCount = tileRequestResult.requestedTilesCount
        let renderedTilesCount = placeTilesContext.tilePlacements.count

        frameContext.sharedState.tilePlacementState = TilePlacementState(
            placeTilesContext: placeTilesContext,
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

    func encode(pass _: RenderPass, encoder _: MTLRenderCommandEncoder, frameContext _: FrameContext) {}

    func handleMemoryWarning() {
        tileRenderStore.handleMemoryWarning()
        placeTilesContext = .empty
        preprocessedVisibleTilesHashTracker.invalidate()
        placementVersion &+= 1
    }

    func evict() {
        tileRenderStore.evict()
        placeTilesContext = .empty
        preprocessedVisibleTilesHashTracker.invalidate()
        placementVersion &+= 1
    }

    private func deduplicateSourceTiles(_ targets: [VisibleTile]) -> [Tile] {
        var uniqueTiles: [Tile] = []
        uniqueTiles.reserveCapacity(targets.count)
        var seenTiles: Set<Tile> = []
        for target in targets {
            let source = target.tile
            if seenTiles.insert(source).inserted {
                uniqueTiles.append(source)
            }
        }
        return uniqueTiles
    }
}
