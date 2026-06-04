// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import QuartzCore

final class ImmersiveMapFrameRenderDelegate: ImmersiveMapRenderDriverFrameDelegate {
    private let layer: CAMetalLayer
    private let renderRuntime: ImmersiveMapRenderRuntime
    private let viewportRuntime: ImmersiveMapViewportRuntime
    private let cameraAnimationRuntime: ImmersiveMapCameraAnimationRuntime

    init(layer: CAMetalLayer,
         renderRuntime: ImmersiveMapRenderRuntime,
         viewportRuntime: ImmersiveMapViewportRuntime,
         cameraAnimationRuntime: ImmersiveMapCameraAnimationRuntime) {
        self.layer = layer
        self.renderRuntime = renderRuntime
        self.viewportRuntime = viewportRuntime
        self.cameraAnimationRuntime = cameraAnimationRuntime
    }

    func renderDriverDidTick(_ driver: ImmersiveMapRenderDriver,
                             currentTime: CFTimeInterval) {
        guard renderRuntime.beginFrame() else {
            return
        }

        prepareRenderLoopFrame(currentTime: currentTime)
        guard renderRuntime.continueFrameAfterPreparation() else {
            return
        }

        renderRuntime.renderFrame(layer: layer,
                                  viewportRuntime: viewportRuntime)
    }

    private func prepareRenderLoopFrame(currentTime: CFTimeInterval) {
        cameraAnimationRuntime.advanceAnimationsIfNeeded(currentTime: currentTime)
    }
}
