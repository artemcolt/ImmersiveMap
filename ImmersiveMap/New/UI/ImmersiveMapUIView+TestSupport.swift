// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import QuartzCore
import UIKit

#if DEBUG
extension ImmersiveMapUIView {
    func flyForTesting(to cameraPosition: ImmersiveMapCameraPosition,
                       options: CameraFlightOptions = .default,
                       completion: ((Bool) -> Void)? = nil,
                       currentTime: CFTimeInterval) {
        startCameraFlight(to: cameraPosition,
                          options: options,
                          completion: completion,
                          currentTime: currentTime)
    }

    func advanceCameraFlightForTesting(currentTime: CFTimeInterval) {
        advanceCameraFlightIfNeeded(currentTime: currentTime)
    }

    func setPanInteractionActiveForTesting(_ isActive: Bool) {
        let wasInteracting = hasActiveUserInteraction
        panInteractionActive = isActive
        if isActive && !wasInteracting {
            cameraController?.notifyUserInteractionBegan()
        }
        if isActive {
            cancelCameraAnimations()
        }
        updateCombinedInteractionRenderingState()
    }

    var hasActiveCameraFlightForTesting: Bool {
        cameraFlightAnimator.isActive
    }

    var isCameraAnimationRenderingActiveForTesting: Bool {
        mapRenderLoop.cameraAnimationRenderingActive
    }

    func simulateBackgroundTapForTesting(at point: CGPoint) {
        handleBackgroundTap(at: point)
    }

    func simulateMapTapForTesting(at point: CGPoint) {
        handleMapTap(at: point)
    }

    func setAvatarSelectionSnapshotForTesting(_ snapshot: AvatarSelectionSnapshot) {
        avatarSelectionSnapshot = snapshot
    }

    func syncAnchoredCameraForTesting() {
        syncAnchoredCameraToMarkerIfNeeded()
    }
}
#endif
