// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import simd

enum ScreenSpaceProjectionMode {
    case globe
    case flat
}

struct ImmersiveMapPresentationState {
    var transition: Float
}

struct SemanticWorldState {
    let cameraState: ImmersiveMapCameraState
}

struct RenderNormalizationState {
    let zoomScale: Double
    let globeRenderRadius: Double
    let flatRenderMapSize: Double
}

struct GlobeRenderState {
    var pan: SIMD2<Double>
    var renderRadius: Double
    var globeUniform: Globe
}

struct FlatRenderState {
    var pan: SIMD2<Double>
    var renderMapSize: Double
}

struct ResolvedPresentationState {
    let semanticWorldState: SemanticWorldState
    let presentationState: ImmersiveMapPresentationState
    let renderNormalizationState: RenderNormalizationState
    let renderSurfaceMode: ViewMode
    let screenSpaceProjectionMode: ScreenSpaceProjectionMode
    let globeRenderState: GlobeRenderState
    let flatRenderState: FlatRenderState

    var transition: Float {
        presentationState.transition
    }

    var globeRenderUniform: Globe {
        globeRenderState.globeUniform
    }

    var cameraState: ImmersiveMapCameraState {
        semanticWorldState.cameraState
    }

    var flatProjectionInputsEnabled: Bool {
        screenSpaceProjectionMode == .flat
    }
}

struct PresentationStateResolver {
    static func resolve(cameraState: ImmersiveMapCameraState,
                        renderSurfaceMode: ViewMode) -> ResolvedPresentationState {
        resolve(cameraState: cameraState,
                settings: ImmersiveMapSettings.default.presentation,
                renderSurfaceMode: renderSurfaceMode)
    }

    static func resolve(cameraState: ImmersiveMapCameraState,
                        settings: ImmersiveMapSettings.PresentationSettings,
                        renderSurfaceMode: ViewMode) -> ResolvedPresentationState {
        let renderZoomScale = pow(2.0, floor(cameraState.zoom))
        let transition = transition(for: renderSurfaceMode)
        let globeRenderRadius = settings.globeRadiusScale * renderZoomScale
        let flatRenderMapSize = 2.0 * Double.pi * globeRenderRadius
        let globePan = ImmersiveMapProjection.globePan(fromCenterWorldMercator: cameraState.centerWorldMercator)
        let flatPan = ImmersiveMapProjection.flatPan(fromCenterWorldMercator: cameraState.centerWorldMercator)

        let globe = Globe(panX: Float(globePan.x),
                          panY: Float(globePan.y),
                          radius: Float(globeRenderRadius),
                          transition: transition)
        let screenSpaceProjectionMode = resolveScreenSpaceProjectionMode(renderSurfaceMode: renderSurfaceMode)

        return ResolvedPresentationState(
            semanticWorldState: SemanticWorldState(cameraState: cameraState),
            presentationState: ImmersiveMapPresentationState(transition: transition),
            renderNormalizationState: RenderNormalizationState(zoomScale: renderZoomScale,
                                                               globeRenderRadius: globeRenderRadius,
                                                               flatRenderMapSize: flatRenderMapSize),
            renderSurfaceMode: renderSurfaceMode,
            screenSpaceProjectionMode: screenSpaceProjectionMode,
            globeRenderState: GlobeRenderState(pan: globePan,
                                               renderRadius: globeRenderRadius,
                                               globeUniform: globe),
            flatRenderState: FlatRenderState(pan: flatPan,
                                             renderMapSize: flatRenderMapSize)
        )
    }

    private static func transition(for renderSurfaceMode: ViewMode) -> Float {
        renderSurfaceMode == .flat ? 1.0 : 0.0
    }

    private static func resolveScreenSpaceProjectionMode(renderSurfaceMode: ViewMode) -> ScreenSpaceProjectionMode {
        renderSurfaceMode == .flat ? .flat : .globe
    }
}
