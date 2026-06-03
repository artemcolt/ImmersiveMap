// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import simd

enum ProjectionPolicy {
    case automatic
    case forcedGlobe
    case forcedFlat
}

enum ScreenSpaceProjectionMode {
    case globe
    case flat
}

struct ImmersiveMapPresentationState {
    var projectionBlend: Float
    var projectionPolicy: ProjectionPolicy
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
    let renderBackendMode: ViewMode
    let screenSpaceProjectionMode: ScreenSpaceProjectionMode
    let globeRenderState: GlobeRenderState
    let flatRenderState: FlatRenderState

    var transition: Float {
        presentationState.projectionBlend
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

struct CameraBearingConstraint {
    let maximumAbsoluteBearing: Float?

    func apply(to bearing: Float) -> Float {
        let normalizedBearing = CameraBearingConstraintResolver.normalized(bearing)
        guard let maximumAbsoluteBearing else {
            return normalizedBearing
        }

        let clampedLimit = min(max(maximumAbsoluteBearing, 0), .pi)
        return min(max(normalizedBearing, -clampedLimit), clampedLimit)
    }
}

struct CameraPitchConstraint {
    let maximumPitch: Float

    func apply(to pitch: Float) -> Float {
        let clampedMaximumPitch = max(maximumPitch, 0)
        return min(max(pitch, 0), clampedMaximumPitch)
    }
}

enum CameraBearingConstraintResolver {
    static func resolve(cameraState: ImmersiveMapCameraState,
                        settings: ImmersiveMapSettings,
                        projectionPolicy: ProjectionPolicy) -> CameraBearingConstraint {
        let resolvedPresentation = ViewModeCalculator.resolve(cameraState: cameraState,
                                                              settings: settings.presentation,
                                                              projectionPolicy: projectionPolicy)
        guard resolvedPresentation.renderBackendMode == .spherical else {
            return CameraBearingConstraint(maximumAbsoluteBearing: nil)
        }

        return CameraBearingConstraint(
            maximumAbsoluteBearing: globeMaximumAbsoluteBearing(zoom: cameraState.zoom,
                                                                cameraSettings: settings.camera)
        )
    }

    static func globeMaximumAbsoluteBearing(zoom: Double,
                                            cameraSettings: ImmersiveMapSettings.CameraSettings) -> Float {
        let minimumBearing = min(max(cameraSettings.globeMinimumAbsoluteBearing, 0), .pi)
        let unlockZoom = max(cameraSettings.globeBearingUnlockZoom, 0)
        guard unlockZoom > Double.leastNonzeroMagnitude else {
            return .pi
        }

        let progress = min(max(zoom / unlockZoom, 0), 1)
        return minimumBearing + (Float.pi - minimumBearing) * Float(progress)
    }

    static func normalized(_ bearing: Float) -> Float {
        let twoPi = Float.pi * 2
        var normalized = (bearing + .pi).truncatingRemainder(dividingBy: twoPi)
        if normalized < 0 {
            normalized += twoPi
        }
        return normalized - .pi
    }
}

enum CameraPitchConstraintResolver {
    static func resolve(cameraState: ImmersiveMapCameraState,
                        settings: ImmersiveMapSettings,
                        projectionPolicy: ProjectionPolicy) -> CameraPitchConstraint {
        let resolvedPresentation = ViewModeCalculator.resolve(cameraState: cameraState,
                                                              settings: settings.presentation,
                                                              projectionPolicy: projectionPolicy)
        guard resolvedPresentation.renderBackendMode == .spherical else {
            return CameraPitchConstraint(maximumPitch: settings.camera.maximumReachablePitch(at: cameraState.zoom))
        }

        return CameraPitchConstraint(
            maximumPitch: globeMaximumPitch(zoom: cameraState.zoom,
                                            cameraSettings: settings.camera)
        )
    }

    static func globeMaximumPitch(zoom: Double,
                                  cameraSettings: ImmersiveMapSettings.CameraSettings) -> Float {
        let maximumPitch = cameraSettings.maximumReachablePitch(at: zoom)
        let unlockZoom = max(cameraSettings.globePitchUnlockZoom, 0)
        guard unlockZoom > Double.leastNonzeroMagnitude else {
            return maximumPitch
        }

        let progress = min(max(zoom / unlockZoom, 0), 1)
        return maximumPitch * Float(progress)
    }
}

struct ViewModeCalculator {
    static func resolve(cameraState: ImmersiveMapCameraState,
                        projectionPolicy: ProjectionPolicy) -> ResolvedPresentationState {
        resolve(cameraState: cameraState,
                settings: ImmersiveMapSettings.default.presentation,
                projectionPolicy: projectionPolicy)
    }

    static func resolve(cameraState: ImmersiveMapCameraState,
                        settings: ImmersiveMapSettings.PresentationSettings,
                        projectionPolicy: ProjectionPolicy) -> ResolvedPresentationState {
        let renderZoomScale = pow(2.0, floor(cameraState.zoom))
        let automaticBlend = automaticProjectionBlend(zoom: cameraState.zoom, settings: settings)
        let projectionBlend = resolvedProjectionBlend(automaticBlend: automaticBlend,
                                                      projectionPolicy: projectionPolicy)
        let globeRenderRadius = settings.globeRadiusScale * renderZoomScale
        let flatRenderMapSize = 2.0 * Double.pi * globeRenderRadius
        let globePan = ImmersiveMapProjection.globePan(fromCenterWorldMercator: cameraState.centerWorldMercator)
        let flatPan = ImmersiveMapProjection.flatPan(fromCenterWorldMercator: cameraState.centerWorldMercator)

        let globe = Globe(panX: Float(globePan.x),
                          panY: Float(globePan.y),
                          radius: Float(globeRenderRadius),
                          transition: projectionBlend)
        let renderBackendMode = resolveRenderBackendMode(projectionBlend: projectionBlend)
        let screenSpaceProjectionMode = resolveScreenSpaceProjectionMode(renderBackendMode: renderBackendMode)

        return ResolvedPresentationState(
            semanticWorldState: SemanticWorldState(cameraState: cameraState),
            presentationState: ImmersiveMapPresentationState(projectionBlend: projectionBlend,
                                                    projectionPolicy: projectionPolicy),
            renderNormalizationState: RenderNormalizationState(zoomScale: renderZoomScale,
                                                               globeRenderRadius: globeRenderRadius,
                                                               flatRenderMapSize: flatRenderMapSize),
            renderBackendMode: renderBackendMode,
            screenSpaceProjectionMode: screenSpaceProjectionMode,
            globeRenderState: GlobeRenderState(pan: globePan,
                                               renderRadius: globeRenderRadius,
                                               globeUniform: globe),
            flatRenderState: FlatRenderState(pan: flatPan,
                                             renderMapSize: flatRenderMapSize)
        )
    }

    private static func automaticProjectionBlend(zoom: Double,
                                                 settings: ImmersiveMapSettings.PresentationSettings) -> Float {
        let from = Float(settings.automaticTransitionStartZoom)
        let span = max(Float.leastNonzeroMagnitude, Float(settings.automaticTransitionSpan))
        let to = from + span
        return max(0.0, min(1.0, (Float(zoom) - from) / (to - from)))
    }

    private static func resolvedProjectionBlend(automaticBlend: Float,
                                                projectionPolicy: ProjectionPolicy) -> Float {
        switch projectionPolicy {
        case .automatic:
            return automaticBlend
        case .forcedGlobe:
            return 0.0
        case .forcedFlat:
            return 1.0
        }
    }

    private static func resolveRenderBackendMode(projectionBlend: Float) -> ViewMode {
        projectionBlend >= 1.0 ? .flat : .spherical
    }

    private static func resolveScreenSpaceProjectionMode(renderBackendMode: ViewMode) -> ScreenSpaceProjectionMode {
        renderBackendMode == .flat ? .flat : .globe
    }
}
