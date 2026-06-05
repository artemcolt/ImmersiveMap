// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

/// Вычисляет видимый tile content для кадра на основе camera snapshot, presentation state и tile settings.
final class RenderFrameVisibilityResolver {
    private let tileCulling: TileCulling

    init(tileCulling: TileCulling = TileCulling()) {
        self.tileCulling = tileCulling
    }

    func resolve(cameraFrameState: CameraFrameState,
                 resolvedPresentation: ResolvedPresentationState,
                 tileSettings: ImmersiveMapSettings.TileSettings,
                 diagnostics: (any FrameDiagnosticsService)? = nil) -> VisibleContentState {
        let targetTileZoom = tileSettings.resolvedCoverageZoomLevel(forCameraZoom: cameraFrameState.mapCameraState.zoom)
        return tileCulling.resolveVisibleContent(cameraState: cameraFrameState.mapCameraState,
                                                 resolvedPresentation: resolvedPresentation,
                                                 targetZoom: targetTileZoom,
                                                 cameraMatrix: cameraFrameState.cameraMatrices.projectionView,
                                                 cameraFrustum: cameraFrameState.cameraFrustum,
                                                 cameraEye: cameraFrameState.cameraEye,
                                                 diagnostics: diagnostics)
    }
}
