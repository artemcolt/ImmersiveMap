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
    let cameraFrustum: Frustum?
    let mapCameraState: ImmersiveMapCameraState
    let qualityTier: RenderQualityTier
}

/// Отвечает за подготовку состояния камеры для кадра рендера:
/// синхронизирует управляющую камеру с render-камерой, применяет ограничения
/// и собирает матрицы, frustum, eye position и camera state для frame pipeline.
final class FrameCameraStateResolver {
    private static let flatPlaneIntersectionTolerance: Float = 1e-5

    private let camera: RenderCamera
    private let cameraStateController: CameraStateController
    private let cameraPoseResolver: RenderCameraPoseResolver
    private let screenMatrix: ScreenMatrix
    private var lastDrawableSize: CGSize = .zero

    init(settings: ImmersiveMapSettings) {
        self.camera = RenderCamera()
        self.cameraStateController = CameraStateController(settings: settings.camera)
        self.cameraPoseResolver = RenderCameraPoseResolver()
        self.screenMatrix = ScreenMatrix()
        RendererSetup.configureCamera(cameraStateController)
        requestRenderCameraUpdate()
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

        cameraPoseResolver.updateIfNeeded(camera: camera, cameraState: cameraStateController.cameraState)
        guard let cameraMatrix = camera.cameraMatrix,
              let cameraView = camera.view else {
            diagnostics.recordSkipReason(.missingCameraState)
            return nil
        }

        let matrices = FrameCameraMatrices(projectionView: cameraMatrix,
                                           view: cameraView,
                                           screen: screenMatrixValue)

        return CameraFrameState(drawSize: drawSize,
                                viewport: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                                cameraMatrices: matrices,
                                cameraEye: camera.eye,
                                cameraFrustum: camera.frustrum,
                                mapCameraState: cameraStateController.cameraState,
                                qualityTier: RenderQualityTier.from(zoom: cameraStateController.zoom))
    }

    func rotateCameraYaw(delta: Float) {
        cameraStateController.rotateYaw(delta: delta)
        requestRenderCameraUpdate()
    }

    func panCamera(deltaX: Double, deltaY: Double) {
        cameraStateController.pan(deltaX: deltaX, deltaY: deltaY)
        requestRenderCameraUpdate()
    }

    func zoomCamera(scale: Double, velocity: Double = 0) {
        cameraStateController.zoom(scale: scale, velocity: velocity)
        requestRenderCameraUpdate()
    }

    func zoomCamera(delta: Double) {
        cameraStateController.zoom(delta: delta)
        requestRenderCameraUpdate()
    }

    func setCameraPitch(_ pitch: Float) {
        cameraStateController.setPitch(pitch)
        requestRenderCameraUpdate()
    }

    func setCameraPosition(_ cameraPosition: ImmersiveMapCameraPosition) {
        cameraStateController.setCameraPosition(cameraPosition)
        requestRenderCameraUpdate()
    }

    func setCameraState(_ cameraState: ImmersiveMapCameraState) {
        cameraStateController.setCameraState(cameraState)
        requestRenderCameraUpdate()
    }

    func setCenterWorldMercator(_ centerWorldMercator: SIMD2<Double>) {
        cameraStateController.setCenterWorldMercator(centerWorldMercator)
        requestRenderCameraUpdate()
    }

    func currentCameraPosition() -> ImmersiveMapCameraPosition {
        let latLon = cameraStateController.getLatLonDeg()
        return ImmersiveMapCameraPosition(latitudeDegrees: latLon.latDeg,
                                          longitudeDegrees: latLon.lonDeg,
                                          zoom: cameraStateController.zoom,
                                          bearing: cameraStateController.yaw,
                                          pitch: cameraStateController.pitch)
    }

    func currentCameraState() -> ImmersiveMapCameraState {
        cameraStateController.currentCameraState()
    }

    func applyCameraSettings(_ settings: ImmersiveMapSettings.CameraSettings) {
        cameraStateController.apply(settings: settings)
        requestRenderCameraUpdate()
    }

    func applyConstraints(_ constraints: CameraConstraints) {
        cameraStateController.clampBearing(to: constraints.bearing)
        cameraStateController.clampPitch(to: constraints.pitch)
        requestRenderCameraUpdate()
    }

    @discardableResult
    func prepareForInput(drawableSize: CGSize) -> Bool {
        guard drawableSize.width > 0,
              drawableSize.height > 0 else {
            return false
        }

        if drawableSize != lastDrawableSize {
            let aspect = Float(drawableSize.width) / Float(drawableSize.height)
            camera.recalculateProjection(aspect: aspect)
            lastDrawableSize = drawableSize
        }

        cameraPoseResolver.updateIfNeeded(camera: camera, cameraState: cameraStateController.cameraState)
        return camera.cameraMatrix != nil
    }

    func renderPointOnZeroZPlane(at drawablePoint: CGPoint,
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

    private func requestRenderCameraUpdate() {
        cameraPoseResolver.requestUpdate()
    }
}
