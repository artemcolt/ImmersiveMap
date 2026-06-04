// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import simd

struct RenderCameraConstraints {
    let bearing: CameraBearingConstraint
    let pitch: CameraPitchConstraint
}

/// Координирует presentation state карты: projection policy, flat/globe surface mode и camera constraints.
final class RenderPresentationCoordinator {
    private var settings: ImmersiveMapSettings
    private var projectionPolicy: ProjectionPolicy = .automatic

    init(settings: ImmersiveMapSettings) {
        self.settings = settings
    }

    func applySettings(_ settings: ImmersiveMapSettings) {
        self.settings = settings
    }

    func resolve(cameraState: ImmersiveMapCameraState) -> ResolvedPresentationState {
        PresentationStateResolver.resolve(cameraState: cameraState,
                                          settings: settings.presentation,
                                          projectionPolicy: projectionPolicy)
    }

    func switchProjectionPolicy(cameraState: ImmersiveMapCameraState) {
        let resolvedPresentation = resolve(cameraState: cameraState)

        switch projectionPolicy {
        case .automatic:
            switch resolvedPresentation.renderSurfaceMode {
            case .spherical:
                projectionPolicy = .forcedFlat
            case .flat:
                projectionPolicy = .forcedGlobe
            }
        case .forcedGlobe, .forcedFlat:
            projectionPolicy = .automatic
        }
    }

    func isSphericalSurfaceActive(cameraState: ImmersiveMapCameraState) -> Bool {
        resolve(cameraState: cameraState).renderSurfaceMode == .spherical
    }

    func cameraConstraints(cameraState: ImmersiveMapCameraState) -> RenderCameraConstraints {
        RenderCameraConstraints(bearing: cameraBearingConstraint(cameraState: cameraState),
                                pitch: cameraPitchConstraint(cameraState: cameraState))
    }

    func cameraBearingConstraint(cameraState: ImmersiveMapCameraState) -> CameraBearingConstraint {
        CameraBearingConstraintResolver.resolve(cameraState: cameraState,
                                                settings: settings,
                                                projectionPolicy: projectionPolicy)
    }

    func cameraPitchConstraint(cameraState: ImmersiveMapCameraState) -> CameraPitchConstraint {
        CameraPitchConstraintResolver.resolve(cameraState: cameraState,
                                              settings: settings,
                                              projectionPolicy: projectionPolicy)
    }

    func zoomCamera(_ renderCamera: ImmersiveMapRenderCamera,
                    delta: Double,
                    anchorDrawablePoint: CGPoint,
                    drawableSize: CGSize) {
        guard delta.isFinite, delta != 0 else {
            return
        }

        guard drawableSize.width > 0,
              drawableSize.height > 0 else {
            zoomCamera(renderCamera, delta: delta)
            return
        }

        let cameraStateBefore = renderCamera.currentCameraState()
        let resolvedBefore = resolve(cameraState: cameraStateBefore)
        guard resolvedBefore.screenSpaceProjectionMode == .flat,
              renderCamera.prepareForInput(drawableSize: drawableSize),
              let anchorRenderPointBefore = renderCamera.renderPointOnZeroZPlane(at: anchorDrawablePoint,
                                                                                 drawableSize: drawableSize),
              let anchoredWorldCoordinate = flatWorldCoordinate(forRenderPoint: anchorRenderPointBefore,
                                                                flatRenderState: resolvedBefore.flatRenderState,
                                                                cameraState: cameraStateBefore) else {
            zoomCamera(renderCamera, delta: delta)
            return
        }

        zoomCamera(renderCamera, delta: delta)

        let cameraStateAfter = renderCamera.currentCameraState()
        let resolvedAfter = resolve(cameraState: cameraStateAfter)
        guard resolvedAfter.screenSpaceProjectionMode == .flat,
              renderCamera.prepareForInput(drawableSize: drawableSize),
              let anchorRenderPointAfter = renderCamera.renderPointOnZeroZPlane(at: anchorDrawablePoint,
                                                                                drawableSize: drawableSize),
              let worldCoordinateAfterZoom = flatWorldCoordinate(forRenderPoint: anchorRenderPointAfter,
                                                                 flatRenderState: resolvedAfter.flatRenderState,
                                                                 cameraState: cameraStateAfter) else {
            return
        }

        let deltaX = shortestWrappedDelta(from: worldCoordinateAfterZoom.x,
                                          to: anchoredWorldCoordinate.x)
        let deltaY = anchoredWorldCoordinate.y - worldCoordinateAfterZoom.y
        renderCamera.setCenterWorldMercator(cameraStateAfter.centerWorldMercator + SIMD2<Double>(deltaX, deltaY))
    }

    func zoomCamera(_ renderCamera: ImmersiveMapRenderCamera,
                    delta: Double) {
        renderCamera.zoomCamera(delta: delta)
        applyCameraConstraints(to: renderCamera)
    }

    func applyCameraConstraints(to renderCamera: ImmersiveMapRenderCamera) {
        renderCamera.applyConstraints(cameraConstraints(cameraState: renderCamera.currentCameraState()))
    }

    private func flatWorldCoordinate(forRenderPoint point: SIMD2<Double>,
                                     flatRenderState: FlatRenderState,
                                     cameraState: ImmersiveMapCameraState) -> SIMD2<Double>? {
        let renderMapSize = flatRenderState.renderMapSize
        guard renderMapSize.isFinite, renderMapSize > 0 else {
            return nil
        }

        let center = cameraState.centerWorldMercator
        let x = ImmersiveMapProjection.wrapNormalizedWorldX(center.x + point.x / renderMapSize)
        let y = ImmersiveMapProjection.clampNormalizedWorldY(center.y - point.y / renderMapSize)
        return SIMD2<Double>(x, y)
    }

    private func shortestWrappedDelta(from current: Double,
                                      to target: Double) -> Double {
        var delta = target - current
        if delta > 0.5 {
            delta -= 1.0
        } else if delta < -0.5 {
            delta += 1.0
        }
        return delta
    }
}
