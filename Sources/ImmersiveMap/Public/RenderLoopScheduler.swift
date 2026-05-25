//
//  RenderLoopScheduler.swift
//  ImmersiveMapFramework
//

import Foundation

final class RenderLoopScheduler {
    private var configuration: MapSettings.RenderLoopSettings

    private(set) var pendingFrame: Bool = false
    private(set) var interactionRenderingActive: Bool = false
    private(set) var labelFadeRenderingActive: Bool = false
    private(set) var labelVisibilityCycleRenderingActive: Bool = false
    private(set) var cameraAnimationRenderingActive: Bool = false
    private(set) var avatarAnimationRenderingActive: Bool = false

    init(configuration: MapSettings.RenderLoopSettings) {
        self.configuration = configuration
    }

    convenience init(forceContinuousRendering: Bool) {
        var configuration = MapSettings.default.renderLoop
        configuration.forceContinuousRendering = forceContinuousRendering
        self.init(configuration: configuration)
    }

    func updateConfiguration(_ configuration: MapSettings.RenderLoopSettings) {
        self.configuration = configuration
    }

    var shouldRenderFrame: Bool {
        configuration.forceContinuousRendering
            || pendingFrame
            || interactionRenderingActive
            || labelFadeRenderingActive
            || labelVisibilityCycleRenderingActive
            || cameraAnimationRenderingActive
            || avatarAnimationRenderingActive
    }

    var shouldPauseDisplayLink: Bool {
        shouldRenderFrame == false
    }

    var preferredFramesPerSecond: Int {
        if configuration.forceContinuousRendering {
            return configuration.interactionFramesPerSecond
        }
        if interactionRenderingActive {
            return configuration.interactionFramesPerSecond
        }
        if labelVisibilityCycleRenderingActive {
            return configuration.interactionFramesPerSecond
        }
        if cameraAnimationRenderingActive {
            return configuration.interactionFramesPerSecond
        }
        if avatarAnimationRenderingActive {
            return configuration.interactionFramesPerSecond
        }
        if labelFadeRenderingActive {
            return configuration.labelFadeFramesPerSecond
        }
        return 0
    }

    func requestFrame() {
        pendingFrame = true
    }

    func setLabelFadeRenderingActive(_ isActive: Bool) {
        labelFadeRenderingActive = isActive
    }

    func setBaseLabelFadeRenderingActive(_ isActive: Bool) {
        setLabelFadeRenderingActive(isActive)
    }

    func setLabelVisibilityCycleRenderingActive(_ isActive: Bool) {
        labelVisibilityCycleRenderingActive = isActive
    }

    func setInteractionRenderingActive(_ isActive: Bool) {
        interactionRenderingActive = isActive
    }

    func setCameraAnimationRenderingActive(_ isActive: Bool) {
        cameraAnimationRenderingActive = isActive
    }

    func setAvatarAnimationRenderingActive(_ isActive: Bool) {
        avatarAnimationRenderingActive = isActive
    }

    func markFrameScheduled() {
        pendingFrame = false
    }
}
