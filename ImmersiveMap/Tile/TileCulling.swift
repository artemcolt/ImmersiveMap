// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

class TileCulling {
    let camera: Camera
    private let globeVisibleTileResolver: any GlobeVisibleTileResolving
    private var coverageVersion: UInt64 = 0

    init(camera: Camera,
         globeVisibleTileResolver: (any GlobeVisibleTileResolving)? = nil) {
        self.camera = camera
        self.globeVisibleTileResolver = globeVisibleTileResolver ?? GlobeVisibleTileResolver(camera: camera)
    }

    func resolveVisibleContent(cameraState: ImmersiveMapCameraState,
                               resolvedPresentation: ResolvedPresentationState,
                               targetZoom: Int,
                               diagnostics: (any FrameDiagnosticsService)? = nil) -> VisibleContentState {
        let semanticCenterWorldMercator = cameraState.centerWorldMercator
        let center = makeCenter(centerWorldMercator: semanticCenterWorldMercator,
                                targetZoom: targetZoom)
        let visibleTiles: [VisibleTile]

        switch resolvedPresentation.renderBackendMode {
        case .spherical:
            let resolution = iSeeTilesGlobe(targetZoom: targetZoom,
                                            center: center,
                                            globeRenderState: resolvedPresentation.globeRenderState)
            visibleTiles = resolution.visibleTiles
            recordGlobeMetrics(resolution.metrics, diagnostics: diagnostics)
        case .flat:
            visibleTiles = Array(iSeeTilesFlat(targetZoom: targetZoom,
                                               center: center,
                                               flatRenderState: resolvedPresentation.flatRenderState))
        }

        coverageVersion &+= 1
        return VisibleContentState(centerWorldMercator: semanticCenterWorldMercator,
                                   center: center,
                                   visibleTiles: visibleTiles,
                                   tileZoomLevel: targetZoom,
                                   coverageVersion: coverageVersion)
    }

    func iSeeTilesGlobe(targetZoom: Int,
                        center: Center,
                        globeRenderState: GlobeRenderState) -> GlobeVisibleTileResolution {
        let tileX = Int(center.tileX)
        let tileY = Int(center.tileY)

        #if DEBUG
        print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
        #endif

        return globeVisibleTileResolver.resolveVisibleTiles(targetZoom: targetZoom,
                                                            globe: globeRenderState.globeUniform)
    }

    func iSeeTilesFlat(targetZoom: Int,
                       center: Center,
                       flatRenderState: FlatRenderState) -> Set<VisibleTile> {
        let tileX = Int(center.tileX)
        let tileY = Int(center.tileY)

        #if DEBUG
        print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
        #endif

        return FlatVisibleTileResolver.resolveVisibleTiles(targetZoom: targetZoom,
                                                           flatRenderState: flatRenderState,
                                                           camera: camera)
    }

    private func makeCenter(centerWorldMercator: SIMD2<Double>,
                            targetZoom: Int) -> Center {
        let tilesCount = Double(1 << targetZoom)
        return Center(tileX: ImmersiveMapProjection.wrapNormalizedWorldX(centerWorldMercator.x) * tilesCount,
                      tileY: ImmersiveMapProjection.clampNormalizedWorldY(centerWorldMercator.y) * tilesCount)
    }

    private func recordGlobeMetrics(_ metrics: GlobeCullingMetrics,
                                    diagnostics: (any FrameDiagnosticsService)?) {
        diagnostics?.setMeasurement(.globeCullingDurationMs,
                                    value: metrics.duration * 1000.0)
        diagnostics?.setCounter(.globeCullingVisitedNodes,
                                value: metrics.visitedNodeCount)
        diagnostics?.setCounter(.globeCullingFrustumRejects,
                                value: metrics.frustumRejectCount)
        diagnostics?.setCounter(.globeCullingHorizonRejects,
                                value: metrics.horizonRejectCount)
        diagnostics?.setCounter(.globeCullingAcceptedLeafTiles,
                                value: metrics.acceptedLeafTileCount)
        diagnostics?.setCounter(.globeCullingAcceptedWholeSubtrees,
                                value: metrics.acceptedWholeSubtreeCount)
    }
}
