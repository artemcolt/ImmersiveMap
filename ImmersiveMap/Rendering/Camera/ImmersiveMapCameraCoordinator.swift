// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import simd

struct CameraFrameState {
    let drawSize: CGSize
    let viewport: SIMD2<Float>
    let cameraMatrices: FrameCameraMatrices
    let cameraEye: SIMD3<Float>
    let mapCameraState: ImmersiveMapCameraState
    let resolvedPresentation: ResolvedPresentationState
    let visibleContent: VisibleContentState
    let qualityTier: RenderQualityTier
}

final class ImmersiveMapCameraCoordinator {
    private static let flatPlaneIntersectionTolerance: Float = 1e-5

    private var settings: ImmersiveMapSettings
    private let camera: Camera
    private let cameraControl: CameraControl
    private let tileCulling: TileCulling
    private let renderModeController: RenderModeController
    private let screenMatrix: ScreenMatrix
    private var lastDrawableSize: CGSize = .zero

    private(set) var transition: Float = 0

    init(settings: ImmersiveMapSettings) {
        self.settings = settings
        self.camera = Camera()
        self.cameraControl = CameraControl(settings: settings.camera)
        self.tileCulling = TileCulling(camera: camera)
        self.renderModeController = RenderModeController()
        self.screenMatrix = ScreenMatrix()
        RendererSetup.configureCamera(cameraControl)
    }

    func makeFrameState(drawSize: CGSize, diagnostics: FrameDiagnostics) -> CameraFrameState? {
        guard drawSize.width > 0, drawSize.height > 0 else {
            diagnostics.recordSkipReason(.zeroDrawableSize)
            return nil
        }

        if drawSize != lastDrawableSize {
            let aspect = Float(drawSize.width) / Float(drawSize.height)
            camera.recalculateProjection(aspect: aspect)
            lastDrawableSize = drawSize
        }

        screenMatrix.update(drawSize)
        guard let screenMatrixValue = screenMatrix.get() else {
            diagnostics.recordSkipReason(.missingScreenMatrix)
            return nil
        }

        CameraUpdater.updateIfNeeded(camera: camera, cameraControl: cameraControl)
        guard let cameraMatrix = camera.cameraMatrix,
              let cameraView = camera.view else {
            diagnostics.recordSkipReason(.missingCameraState)
            return nil
        }

        let resolvedPresentation = resolvedPresentationState()
        transition = resolvedPresentation.transition
        let targetTileZoom = settings.tiles.resolvedCoverageZoomLevel(forCameraZoom: cameraControl.zoom)
        let visibleContent = tileCulling.resolveVisibleContent(cameraState: cameraControl.cameraState,
                                                               resolvedPresentation: resolvedPresentation,
                                                               targetZoom: targetTileZoom,
                                                               diagnostics: diagnostics)
        let matrices = FrameCameraMatrices(projectionView: cameraMatrix,
                                           view: cameraView,
                                           screen: screenMatrixValue)

        return CameraFrameState(drawSize: drawSize,
                                viewport: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                                cameraMatrices: matrices,
                                cameraEye: camera.eye,
                                mapCameraState: cameraControl.cameraState,
                                resolvedPresentation: resolvedPresentation,
                                visibleContent: visibleContent,
                                qualityTier: RenderQualityTier.from(zoom: cameraControl.zoom))
    }

    func switchRenderMode() {
        let resolvedPresentation = resolvedPresentationState()
        renderModeController.advanceProjectionPolicy(currentResolvedPresentation: resolvedPresentation)
        applyCameraConstraints()
    }

    func rotateCameraYaw(delta: Float) {
        cameraControl.rotateYaw(delta: delta)
        applyCameraBearingConstraint()
    }

    func panCamera(deltaX: Double, deltaY: Double) {
        cameraControl.pan(deltaX: deltaX, deltaY: deltaY)
    }

    func zoomCamera(scale: Double, velocity: Double = 0) {
        cameraControl.zoom(scale: scale, velocity: velocity)
        applyCameraConstraints()
    }

    func zoomCamera(delta: Double) {
        cameraControl.zoom(delta: delta)
        applyCameraConstraints()
    }

    func zoomCamera(delta: Double,
                    anchorDrawablePoint: CGPoint,
                    drawableSize: CGSize) {
        guard delta.isFinite, delta != 0 else {
            return
        }

        guard drawableSize.width > 0,
              drawableSize.height > 0 else {
            zoomCamera(delta: delta)
            return
        }

        let resolvedBefore = resolvedPresentationState()
        guard resolvedBefore.screenSpaceProjectionMode == .flat,
              prepareCameraForInput(drawableSize: drawableSize),
              let anchorRenderPointBefore = flatRenderPoint(at: anchorDrawablePoint,
                                                            drawableSize: drawableSize),
              let anchoredWorldCoordinate = flatWorldCoordinate(forRenderPoint: anchorRenderPointBefore,
                                                                flatRenderState: resolvedBefore.flatRenderState,
                                                                cameraState: cameraControl.currentCameraState()) else {
            zoomCamera(delta: delta)
            return
        }

        cameraControl.zoom(delta: delta)
        applyCameraConstraints()

        let resolvedAfter = resolvedPresentationState()
        guard resolvedAfter.screenSpaceProjectionMode == .flat,
              prepareCameraForInput(drawableSize: drawableSize),
              let anchorRenderPointAfter = flatRenderPoint(at: anchorDrawablePoint,
                                                           drawableSize: drawableSize),
              let worldCoordinateAfterZoom = flatWorldCoordinate(forRenderPoint: anchorRenderPointAfter,
                                                                 flatRenderState: resolvedAfter.flatRenderState,
                                                                 cameraState: cameraControl.currentCameraState()) else {
            return
        }

        let deltaX = shortestWrappedDelta(from: worldCoordinateAfterZoom.x,
                                          to: anchoredWorldCoordinate.x)
        let deltaY = anchoredWorldCoordinate.y - worldCoordinateAfterZoom.y
        cameraControl.setCenterWorldMercator(cameraControl.currentCameraState().centerWorldMercator + SIMD2<Double>(deltaX, deltaY))
    }

    func setCameraPitch(_ pitch: Float) {
        cameraControl.setPitch(pitch)
        applyCameraPitchConstraint()
    }

    func setCameraPosition(_ cameraPosition: ImmersiveMapCameraPosition) {
        cameraControl.setCameraPosition(cameraPosition)
        applyCameraConstraints()
    }

    func setCameraState(_ cameraState: ImmersiveMapCameraState) {
        cameraControl.setCameraState(cameraState)
        applyCameraConstraints()
    }

    func isSphericalRenderBackendActive() -> Bool {
        resolvedPresentationState().renderBackendMode == .spherical
    }

    func currentCameraPosition() -> ImmersiveMapCameraPosition {
        let latLon = cameraControl.getLatLonDeg()
        return ImmersiveMapCameraPosition(latitudeDegrees: latLon.latDeg,
                                          longitudeDegrees: latLon.lonDeg,
                                          zoom: cameraControl.zoom,
                                          bearing: cameraControl.yaw,
                                          pitch: cameraControl.pitch)
    }

    func currentCameraState() -> ImmersiveMapCameraState {
        cameraControl.currentCameraState()
    }

    func applySettings(_ settings: ImmersiveMapSettings) {
        self.settings = settings
        cameraControl.apply(settings: settings.camera)
        applyCameraConstraints()
    }

    func currentMaximumPitch() -> Float {
        cameraPitchConstraint().maximumPitch
    }

    private func applyCameraConstraints() {
        applyCameraBearingConstraint()
        applyCameraPitchConstraint()
    }

    private func resolvedPresentationState() -> ResolvedPresentationState {
        ViewModeCalculator.resolve(cameraState: cameraControl.currentCameraState(),
                                   settings: settings.presentation,
                                   projectionPolicy: renderModeController.projectionPolicy)
    }

    @discardableResult
    private func prepareCameraForInput(drawableSize: CGSize) -> Bool {
        guard drawableSize.width > 0,
              drawableSize.height > 0 else {
            return false
        }

        if drawableSize != lastDrawableSize {
            let aspect = Float(drawableSize.width) / Float(drawableSize.height)
            camera.recalculateProjection(aspect: aspect)
            lastDrawableSize = drawableSize
        }

        CameraUpdater.updateIfNeeded(camera: camera, cameraControl: cameraControl)
        return camera.cameraMatrix != nil
    }

    private func flatRenderPoint(at drawablePoint: CGPoint,
                                 drawableSize: CGSize) -> SIMD2<Double>? {
        guard drawableSize.width > 0,
              drawableSize.height > 0,
              let cameraMatrix = camera.cameraMatrix else {
            return nil
        }

        let x = min(max(drawablePoint.x, 0), drawableSize.width)
        let y = min(max(drawablePoint.y, 0), drawableSize.height)
        let clipX = Float((x / drawableSize.width) * 2.0 - 1.0)
        let clipY = Float(1.0 - (y / drawableSize.height) * 2.0)
        let inverseCameraMatrix = simd_inverse(cameraMatrix)

        guard let nearPoint = unprojectClipSpacePoint(SIMD3<Float>(clipX, clipY, 0),
                                                      inverseCameraMatrix: inverseCameraMatrix),
              let farPoint = unprojectClipSpacePoint(SIMD3<Float>(clipX, clipY, 1),
                                                     inverseCameraMatrix: inverseCameraMatrix) else {
            return nil
        }

        let denominator = nearPoint.z - farPoint.z
        guard abs(denominator) > Self.flatPlaneIntersectionTolerance else {
            return nil
        }

        let t = nearPoint.z / denominator
        guard t.isFinite,
              t >= -Self.flatPlaneIntersectionTolerance,
              t <= 1.0 + Self.flatPlaneIntersectionTolerance else {
            return nil
        }

        let point = nearPoint + (farPoint - nearPoint) * min(max(t, 0), 1)
        guard point.x.isFinite, point.y.isFinite else {
            return nil
        }

        return SIMD2<Double>(Double(point.x), Double(point.y))
    }

    private func unprojectClipSpacePoint(_ point: SIMD3<Float>,
                                         inverseCameraMatrix: matrix_float4x4) -> SIMD3<Float>? {
        let homogenous = inverseCameraMatrix * SIMD4<Float>(point.x, point.y, point.z, 1)
        guard homogenous.w.isFinite,
              abs(homogenous.w) > Self.flatPlaneIntersectionTolerance else {
            return nil
        }

        let worldPoint = homogenous / homogenous.w
        guard worldPoint.x.isFinite,
              worldPoint.y.isFinite,
              worldPoint.z.isFinite else {
            return nil
        }

        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
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

    private func applyCameraBearingConstraint() {
        cameraControl.clampBearing(to: cameraBearingConstraint())
    }

    private func applyCameraPitchConstraint() {
        cameraControl.clampPitch(to: cameraPitchConstraint())
    }

    private func cameraBearingConstraint() -> CameraBearingConstraint {
        CameraBearingConstraintResolver.resolve(cameraState: cameraControl.cameraState,
                                               settings: settings,
                                               projectionPolicy: renderModeController.projectionPolicy)
    }

    private func cameraPitchConstraint() -> CameraPitchConstraint {
        CameraPitchConstraintResolver.resolve(cameraState: cameraControl.cameraState,
                                             settings: settings,
                                             projectionPolicy: renderModeController.projectionPolicy)
    }
}
