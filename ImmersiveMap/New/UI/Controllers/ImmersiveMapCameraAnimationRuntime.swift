// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import QuartzCore

/// Владеет time-based camera animations для одного map view.
/// Координирует camera flights и globe pan inertia, затем синхронизирует render-loop activity.
final class ImmersiveMapCameraAnimationRuntime {
    private let cameraRuntime: ImmersiveMapCameraRuntime
    private let interactionRuntime: ImmersiveMapInteractionRuntime
    private let renderRuntime: ImmersiveMapRenderRuntime
    private lazy var flightController = ImmersiveMapCameraFlightController(
        cameraRuntime: cameraRuntime,
        interactionRuntime: interactionRuntime,
        cameraAnimationRuntime: self,
        renderRuntime: renderRuntime
    )
    private lazy var globeCameraPanInertia = GlobeCameraPanInertia(configuration: makeGlobeCameraPanInertiaConfiguration())
    private var globeCameraPanInertiaIsActive = false

    init(cameraRuntime: ImmersiveMapCameraRuntime,
         interactionRuntime: ImmersiveMapInteractionRuntime,
         renderRuntime: ImmersiveMapRenderRuntime) {
        self.cameraRuntime = cameraRuntime
        self.interactionRuntime = interactionRuntime
        self.renderRuntime = renderRuntime
    }

    var isCameraFlightActive: Bool {
        flightController.isActive
    }

    func updateSettings() {
        globeCameraPanInertiaIsActive = globeCameraPanInertia.updateConfiguration(makeGlobeCameraPanInertiaConfiguration())
        refreshRenderingState()
    }

    func startCameraFlight(to cameraPosition: ImmersiveMapCameraPosition,
                           options: CameraFlightOptions,
                           completion: ((Bool) -> Void)?,
                           currentTime: CFTimeInterval) {
        flightController.start(to: cameraPosition,
                               options: options,
                               completion: completion,
                               currentTime: currentTime)
    }

    func cancelCameraFlight(notifyCompletion: Bool = true) {
        flightController.cancel(notifyCompletion: notifyCompletion)
    }

    func advanceCameraFlightIfNeeded(currentTime: CFTimeInterval) {
        flightController.advanceIfNeeded(currentTime: currentTime)
    }

    func startGlobeCameraPanInertiaIfNeeded(initialVelocity: CGPoint,
                                            currentTime: CFTimeInterval = CACurrentMediaTime()) {
        guard cameraRuntime.isSphericalRenderSurfaceActive() else {
            cancelGlobeCameraPanInertia()
            return
        }

        let didStart = globeCameraPanInertia.start(initialVelocity: initialVelocity,
                                                   currentTime: currentTime)
        globeCameraPanInertiaIsActive = didStart
        refreshRenderingState()
        if didStart {
            renderRuntime.requestFrame()
        }
    }

    func cancelGlobeCameraPanInertia() {
        globeCameraPanInertia.cancel()
        globeCameraPanInertiaIsActive = false
        refreshRenderingState()
    }

    func cancelAnimations(notifyFlightCompletion: Bool = true) {
        cancelGlobeCameraPanInertia()
        flightController.cancel(notifyCompletion: notifyFlightCompletion)
    }

    func advanceAnimationsIfNeeded(currentTime: CFTimeInterval) {
        advanceGlobeCameraPanInertiaIfNeeded(currentTime: currentTime)
        flightController.advanceIfNeeded(currentTime: currentTime)
    }

    func reset() {
        globeCameraPanInertia.cancel()
        globeCameraPanInertiaIsActive = false
        flightController.reset()
        refreshRenderingState()
    }

    private func makeGlobeCameraPanInertiaConfiguration() -> GlobeCameraPanInertia.Configuration {
        let settings = cameraRuntime.currentSettings.camera
        return GlobeCameraPanInertia.Configuration(isEnabled: settings.globePanInertiaEnabled,
                                                   halfLife: settings.globePanInertiaHalfLife,
                                                   activationVelocity: settings.globePanInertiaActivationVelocity,
                                                   stopVelocity: settings.globePanInertiaStopVelocity,
                                                   maximumInitialVelocity: settings.globePanInertiaMaxInitialVelocity)
    }

    private func advanceGlobeCameraPanInertiaIfNeeded(currentTime: CFTimeInterval) {
        guard globeCameraPanInertiaIsActive else {
            refreshRenderingState()
            return
        }

        guard interactionRuntime.hasActiveUserInteraction == false,
              cameraRuntime.isSphericalRenderSurfaceActive() else {
            cancelGlobeCameraPanInertia()
            return
        }

        let step = globeCameraPanInertia.advance(currentTime: currentTime)
        globeCameraPanInertiaIsActive = step.isActive
        if step.translation != .zero {
            let scale = cameraRuntime.currentSettings.camera.gesturePanTranslationScale
            cameraRuntime.panCamera(deltaX: Double(step.translation.x) * scale,
                                    deltaY: Double(step.translation.y) * scale)
        }

        if step.isActive == false {
            refreshRenderingState()
        }
    }

    func refreshRenderingState() {
        renderRuntime.setCameraAnimationRenderingActive(globeCameraPanInertiaIsActive || flightController.isActive)
    }
}
