// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// Владеет mutable camera state одного map view.
/// Оборачивает `ImmersiveMapRenderCamera`, применяет camera changes, хранит settings и запрашивает frames.
final class ImmersiveMapCameraRuntime {
    private let initialCameraPosition: ImmersiveMapCameraPosition?
    let presentationCoordinator: RenderPresentationCoordinator
    private let renderRuntime: ImmersiveMapRenderRuntime
    private let controlsRuntime: ImmersiveMapControlsRuntime
    private weak var controller: ImmersiveMapCameraController?
    private(set) var renderCamera: ImmersiveMapRenderCamera?
    private var settings: ImmersiveMapSettings
    private var appliedCameraPosition: ImmersiveMapCameraPosition?

    init(settings: ImmersiveMapSettings,
         initialCameraPosition: ImmersiveMapCameraPosition?,
         renderRuntime: ImmersiveMapRenderRuntime,
         controlsRuntime: ImmersiveMapControlsRuntime) {
        self.settings = settings
        self.initialCameraPosition = initialCameraPosition
        self.presentationCoordinator = RenderPresentationCoordinator(settings: settings)
        self.renderRuntime = renderRuntime
        self.controlsRuntime = controlsRuntime
    }

    var currentSettings: ImmersiveMapSettings {
        settings
    }

    func isAttachedController(_ cameraController: ImmersiveMapCameraController?) -> Bool {
        controller === cameraController
    }

    func updateSettings(_ settings: ImmersiveMapSettings) {
        self.settings = settings
        presentationCoordinator.applySettings(settings)
        renderCamera?.applyCameraSettings(settings.camera)
        applyCurrentCameraConstraints()
    }

    @MainActor
    func attachController(_ newController: ImmersiveMapCameraController?,
                          commandHandler: ImmersiveMapCameraCommandHandler) {
        guard controller !== newController else {
            return
        }

        controller?.setCommandHandler(nil)
        controller?.updateCurrentCameraPosition(nil)
        controller = newController
        newController?.setCommandHandler { command in
            commandHandler.handle(command)
        }
        newController?.updateCurrentCameraPosition(currentCameraPosition())
        notifyCameraPositionChanged()
    }

    func detachController() {
        controller?.setCommandHandler(nil)
        controller?.updateCurrentCameraPosition(nil)
        controller = nil
    }

    func makeRenderCamera(settings: ImmersiveMapSettings,
                          cameraPosition: ImmersiveMapCameraPosition?) -> ImmersiveMapRenderCamera {
        self.settings = settings
        let renderCamera = ImmersiveMapRenderCamera(settings: settings)
        self.renderCamera = renderCamera
        if let cameraPosition {
            renderCamera.setCameraPosition(cameraPosition)
            appliedCameraPosition = cameraPosition
        }
        applyCurrentCameraConstraints()
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        return renderCamera
    }

    func clearRenderCamera() {
        renderCamera = nil
    }

    func cameraPositionForRendererRecreation() -> ImmersiveMapCameraPosition? {
        currentCameraPosition()
    }

    func currentCameraPosition() -> ImmersiveMapCameraPosition? {
        renderCamera?.currentCameraPosition()
            ?? appliedCameraPosition
            ?? initialCameraPosition
    }

    func currentCameraState() -> ImmersiveMapCameraState? {
        renderCamera?.currentCameraState()
    }

    func currentMaximumPitch() -> Float {
        guard let cameraState = renderCamera?.currentCameraState() else {
            return settings.camera.maximumPitch
        }

        return presentationCoordinator.cameraPitchConstraint(cameraState: cameraState).maximumPitch
    }

    func isSphericalRenderSurfaceActive() -> Bool {
        guard let cameraState = renderCamera?.currentCameraState() else {
            return false
        }

        return presentationCoordinator.isSphericalSurfaceActive(cameraState: cameraState)
    }

    func needsCameraPositionUpdate(_ cameraPosition: ImmersiveMapCameraPosition?) -> Bool {
        appliedCameraPosition != cameraPosition
    }

    func applyCameraPosition(_ cameraPosition: ImmersiveMapCameraPosition?) {
        guard appliedCameraPosition != cameraPosition else {
            return
        }

        appliedCameraPosition = cameraPosition
        guard let cameraPosition else {
            return
        }

        renderCamera?.setCameraPosition(cameraPosition)
        applyCurrentCameraConstraints()
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func setCameraPosition(_ cameraPosition: ImmersiveMapCameraPosition,
                           requestRenderFrame: Bool = true) {
        appliedCameraPosition = cameraPosition
        renderCamera?.setCameraPosition(cameraPosition)
        applyCurrentCameraConstraints()
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        if requestRenderFrame {
            renderRuntime.requestFrame()
        }
    }

    func setCameraState(_ cameraState: ImmersiveMapCameraState) {
        renderCamera?.setCameraState(cameraState)
        applyCurrentCameraConstraints()
        syncPitchControlValue()
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func switchRenderMode() {
        guard let cameraState = renderCamera?.currentCameraState() else {
            return
        }

        presentationCoordinator.switchProjectionPolicy(cameraState: cameraState)
        applyCurrentCameraConstraints()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func rotateCameraYaw(delta: Float) {
        renderCamera?.rotateCameraYaw(delta: delta)
        applyCurrentCameraConstraints()
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func panCamera(deltaX: Double,
                   deltaY: Double) {
        renderCamera?.panCamera(deltaX: deltaX,
                                deltaY: deltaY)
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func zoomCamera(scale: CGFloat,
                    velocity: CGFloat) {
        renderCamera?.zoomCamera(scale: scale,
                                 velocity: velocity)
        applyCurrentCameraConstraints()
        notifyCameraPositionChanged()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func zoomCamera(delta: Double) {
        renderCamera?.zoomCamera(delta: delta)
        applyCurrentCameraConstraints()
        notifyCameraPositionChanged()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func zoomCamera(delta: Double,
                    anchorDrawablePoint: CGPoint,
                    drawableSize: CGSize) {
        guard let renderCamera else {
            return
        }

        presentationCoordinator.zoomCamera(renderCamera,
                                           delta: delta,
                                           anchorDrawablePoint: anchorDrawablePoint,
                                           drawableSize: drawableSize)
        notifyCameraPositionChanged()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func setCameraPitch(_ pitch: Float) {
        renderCamera?.setCameraPitch(pitch)
        applyCurrentCameraConstraints()
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func notifyCameraPositionChanged(_ position: ImmersiveMapCameraPosition? = nil) {
        guard let position = position ?? currentCameraPosition() else {
            return
        }

        controller?.notifyCameraPositionChanged(position)
    }

    func notifyMapBackgroundTap() {
        controller?.notifyMapBackgroundTap()
    }

    func notifyUserInteractionBegan() {
        controller?.notifyUserInteractionBegan()
    }

    func syncPitchControlValue(fallbackCameraPosition: ImmersiveMapCameraPosition? = nil) {
        let currentCameraPosition = renderCamera?.currentCameraPosition()
            ?? fallbackCameraPosition
            ?? appliedCameraPosition
            ?? initialCameraPosition
        controlsRuntime.syncPitch(cameraPosition: currentCameraPosition,
                                  maximumPitch: currentMaximumPitch())
    }

    private func applyCurrentCameraConstraints() {
        guard let renderCamera else {
            return
        }

        presentationCoordinator.applyCameraConstraints(to: renderCamera)
    }
}
