// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import simd

/// Выполняет camera zoom вокруг drawable anchor: для flat surface сохраняет world coordinate под пальцем.
final class AnchoredCameraZoomHandler {
    func zoomCamera(_ renderCamera: FrameCameraStateResolver,
                    delta: Double,
                    anchorDrawablePoint: CGPoint,
                    drawableSize: CGSize,
                    resolvePresentation: (ImmersiveMapCameraState) -> ResolvedPresentationState,
                    applyCameraConstraints: () -> Void) {
        guard delta.isFinite, delta != 0 else {
            return
        }

        guard drawableSize.width > 0,
              drawableSize.height > 0 else {
            zoomCamera(renderCamera,
                       delta: delta,
                       applyCameraConstraints: applyCameraConstraints)
            return
        }

        let cameraStateBefore = renderCamera.currentCameraState()
        let resolvedBefore = resolvePresentation(cameraStateBefore)
        guard resolvedBefore.screenSpaceProjectionMode == .flat,
              renderCamera.prepareForInput(drawableSize: drawableSize),
              let anchorRenderPointBefore = renderCamera.renderPointOnZeroZPlane(at: anchorDrawablePoint,
                                                                                 drawableSize: drawableSize),
              let anchoredWorldCoordinate = flatWorldCoordinate(forRenderPoint: anchorRenderPointBefore,
                                                                flatRenderState: resolvedBefore.flatRenderState,
                                                                cameraState: cameraStateBefore) else {
            zoomCamera(renderCamera,
                       delta: delta,
                       applyCameraConstraints: applyCameraConstraints)
            return
        }

        zoomCamera(renderCamera,
                   delta: delta,
                   applyCameraConstraints: applyCameraConstraints)

        let cameraStateAfter = renderCamera.currentCameraState()
        let resolvedAfter = resolvePresentation(cameraStateAfter)
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

    private func zoomCamera(_ renderCamera: FrameCameraStateResolver,
                            delta: Double,
                            applyCameraConstraints: () -> Void) {
        renderCamera.zoomCamera(delta: delta)
        applyCameraConstraints()
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
