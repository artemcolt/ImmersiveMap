// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

/// Хранит текущий surface mode карты и резолвит presentation state для frame pipeline.
final class MapPresentationStateResolver {
    private var settings: ImmersiveMapSettings
    private(set) var renderSurfaceMode: ViewMode = .spherical

    init(settings: ImmersiveMapSettings) {
        self.settings = settings
    }

    func applySettings(_ settings: ImmersiveMapSettings) {
        self.settings = settings
    }

    func resolve(cameraState: ImmersiveMapCameraState) -> ResolvedPresentationState {
        PresentationStateResolver.resolve(cameraState: cameraState,
                                          settings: settings.presentation,
                                          renderSurfaceMode: renderSurfaceMode)
    }

    func switchRenderSurfaceMode() {
        switch renderSurfaceMode {
        case .spherical:
            renderSurfaceMode = .flat
        case .flat:
            renderSurfaceMode = .spherical
        }
    }

    func isSphericalSurfaceActive() -> Bool {
        renderSurfaceMode == .spherical
    }
}
