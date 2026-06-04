// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

final class ImmersiveMapCameraRuntime {
    private let initialCameraPosition: ImmersiveMapCameraPosition?
    private let renderRuntime: ImmersiveMapRenderRuntime
    private let controlsRuntime: ImmersiveMapControlsRuntime
    private weak var controller: ImmersiveMapCameraController?
    private(set) var coordinator: ImmersiveMapCameraCoordinator?
    private var settings: ImmersiveMapSettings
    private var appliedCameraPosition: ImmersiveMapCameraPosition?

    init(settings: ImmersiveMapSettings,
         initialCameraPosition: ImmersiveMapCameraPosition?,
         renderRuntime: ImmersiveMapRenderRuntime,
         controlsRuntime: ImmersiveMapControlsRuntime) {
        self.settings = settings
        self.initialCameraPosition = initialCameraPosition
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

    func makeCoordinator(settings: ImmersiveMapSettings,
                         cameraPosition: ImmersiveMapCameraPosition?) -> ImmersiveMapCameraCoordinator {
        self.settings = settings
        let coordinator = ImmersiveMapCameraCoordinator(settings: settings)
        self.coordinator = coordinator
        if let cameraPosition {
            coordinator.setCameraPosition(cameraPosition)
            appliedCameraPosition = cameraPosition
        }
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        return coordinator
    }

    func clearCoordinator() {
        coordinator = nil
    }

    func cameraPositionForRendererRecreation() -> ImmersiveMapCameraPosition? {
        currentCameraPosition()
    }

    func currentCameraPosition() -> ImmersiveMapCameraPosition? {
        coordinator?.currentCameraPosition()
            ?? appliedCameraPosition
            ?? initialCameraPosition
    }

    func currentCameraState() -> ImmersiveMapCameraState? {
        coordinator?.currentCameraState()
    }

    func currentMaximumPitch() -> Float {
        coordinator?.currentMaximumPitch() ?? settings.camera.maximumPitch
    }

    func isSphericalRenderBackendActive() -> Bool {
        coordinator?.isSphericalRenderBackendActive() ?? false
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

        coordinator?.setCameraPosition(cameraPosition)
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func setCameraPosition(_ cameraPosition: ImmersiveMapCameraPosition,
                           requestRenderFrame: Bool = true) {
        appliedCameraPosition = cameraPosition
        coordinator?.setCameraPosition(cameraPosition)
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        if requestRenderFrame {
            renderRuntime.requestFrame()
        }
    }

    func setCameraState(_ cameraState: ImmersiveMapCameraState) {
        coordinator?.setCameraState(cameraState)
        syncPitchControlValue()
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func switchRenderMode() {
        coordinator?.switchRenderMode()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func rotateCameraYaw(delta: Float) {
        coordinator?.rotateCameraYaw(delta: delta)
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func panCamera(deltaX: Double,
                   deltaY: Double) {
        coordinator?.panCamera(deltaX: deltaX,
                               deltaY: deltaY)
        notifyCameraPositionChanged()
        renderRuntime.requestFrame()
    }

    func zoomCamera(scale: CGFloat,
                    velocity: CGFloat) {
        coordinator?.zoomCamera(scale: scale,
                                velocity: velocity)
        notifyCameraPositionChanged()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func zoomCamera(delta: Double) {
        coordinator?.zoomCamera(delta: delta)
        notifyCameraPositionChanged()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func zoomCamera(delta: Double,
                    anchorDrawablePoint: CGPoint,
                    drawableSize: CGSize) {
        coordinator?.zoomCamera(delta: delta,
                                anchorDrawablePoint: anchorDrawablePoint,
                                drawableSize: drawableSize)
        notifyCameraPositionChanged()
        syncPitchControlValue()
        renderRuntime.requestFrame()
    }

    func setCameraPitch(_ pitch: Float) {
        coordinator?.setCameraPitch(pitch)
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
        let currentCameraPosition = coordinator?.currentCameraPosition()
            ?? fallbackCameraPosition
            ?? appliedCameraPosition
            ?? initialCameraPosition
        controlsRuntime.syncPitch(cameraPosition: currentCameraPosition,
                                  maximumPitch: currentMaximumPitch())
    }
}
