// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import QuartzCore

final class ImmersiveMapRenderLoop: NSObject {
    private var scheduler: RenderLoopScheduler
    private var displayLink: CADisplayLink?
    private var renderer: Renderer?
    private let layerProvider: () -> CAMetalLayer?
    private let isSurfaceRenderable: () -> Bool
    private let prepareFrame: (CFTimeInterval) -> Void

    init(configuration: ImmersiveMapSettings.RenderLoopSettings,
         layerProvider: @escaping () -> CAMetalLayer?,
         isSurfaceRenderable: @escaping () -> Bool,
         prepareFrame: @escaping (CFTimeInterval) -> Void) {
        self.scheduler = RenderLoopScheduler(configuration: configuration)
        self.layerProvider = layerProvider
        self.isSurfaceRenderable = isSurfaceRenderable
        self.prepareFrame = prepareFrame
        super.init()
    }

    var cameraAnimationRenderingActive: Bool {
        scheduler.cameraAnimationRenderingActive
    }

    func start() {
        guard displayLink == nil else { return }

        displayLink = CADisplayLink(target: self, selector: #selector(renderLoop))
        displayLink?.add(to: .main, forMode: .common)
        applyDisplayLinkState()
    }

    func replaceRenderer(_ renderer: Renderer?) {
        self.renderer = renderer
    }

    func applyRendererSettings(_ settings: ImmersiveMapSettings) {
        renderer?.applySettings(settings)
    }

    func handleMemoryWarning() {
        renderer?.handleMemoryWarning()
    }

    func updateConfiguration(_ configuration: ImmersiveMapSettings.RenderLoopSettings) {
        performOnMain {
            self.scheduler.updateConfiguration(configuration)
            self.applyDisplayLinkState()
        }
    }

    func invalidate(reason: RenderInvalidationReason) {
        performOnMain {
            self.scheduler.requestFrame(reason: reason)
            self.applyDisplayLinkState()
        }
    }

    func applyActivityState(_ state: RenderActivityState) {
        performOnMain {
            self.scheduler.setActivity(.labelFade,
                                       isActive: state.labelFadeRenderingActive)
            self.scheduler.setActivity(.labelVisibilityCycle,
                                       isActive: state.labelVisibilityCycleRenderingActive)
            self.scheduler.setActivity(.avatarAnimation,
                                       isActive: state.avatarAnimationRenderingActive)
            self.applyDisplayLinkState()
        }
    }

    func setLabelFadeRenderingActive(_ isActive: Bool) {
        performOnMain {
            self.scheduler.setActivity(.labelFade,
                                       isActive: isActive)
            self.applyDisplayLinkState()
        }
    }

    func setLabelVisibilityCycleRenderingActive(_ isActive: Bool) {
        performOnMain {
            self.scheduler.setActivity(.labelVisibilityCycle,
                                       isActive: isActive)
            self.applyDisplayLinkState()
        }
    }

    func setAvatarAnimationRenderingActive(_ isActive: Bool) {
        performOnMain {
            self.scheduler.setActivity(.avatarAnimation,
                                       isActive: isActive)
            self.applyDisplayLinkState()
        }
    }

    func setInteractionRenderingActive(_ isActive: Bool) {
        performOnMain {
            self.scheduler.setActivity(.interaction,
                                       isActive: isActive)
            self.applyDisplayLinkState()
        }
    }

    func setCameraAnimationRenderingActive(_ isActive: Bool) {
        performOnMain {
            self.scheduler.setActivity(.cameraAnimation,
                                       isActive: isActive)
            self.applyDisplayLinkState()
        }
    }

    func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func renderLoop() {
        guard scheduler.shouldRenderFrame else {
            applyDisplayLinkState()
            return
        }

        prepareFrame(CACurrentMediaTime())
        guard scheduler.shouldRenderFrame else {
            applyDisplayLinkState()
            return
        }

        let didSchedule = renderFrame()
        if didSchedule {
            scheduler.markFrameScheduled()
        }
        applyDisplayLinkState()
    }

    private func renderFrame() -> Bool {
        guard isSurfaceRenderable(),
              let layer = layerProvider() else {
            return false
        }

        return renderer?.render(to: layer) ?? false
    }

    private func applyDisplayLinkState() {
        displayLink?.preferredFramesPerSecond = scheduler.preferredFramesPerSecond
        displayLink?.isPaused = scheduler.shouldPauseDisplayLink
    }

    deinit {
        invalidateDisplayLink()
    }
}
