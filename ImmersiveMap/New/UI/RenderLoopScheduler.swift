// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  RenderLoopScheduler.swift
//  ImmersiveMap
//

import Foundation

final class RenderLoopScheduler {
    enum Activity: String, CaseIterable {
        case interaction = "interaction"
        case labelFade = "label fade"
        case labelVisibilityCycle = "label visibility cycle"
        case cameraAnimation = "camera animation"
        case avatarAnimation = "avatar animation"

        var usesInteractionFrameRate: Bool {
            switch self {
            case .interaction,
                 .labelVisibilityCycle,
                 .cameraAnimation,
                 .avatarAnimation:
                return true
            case .labelFade:
                return false
            }
        }
    }

    private var configuration: ImmersiveMapSettings.RenderLoopSettings
    private var pendingFrameReason: RenderInvalidationReason?
    private var activeReasons: Set<Activity> = []

    var cameraAnimationRenderingActive: Bool {
        activeReasons.contains(.cameraAnimation)
    }

    init(configuration: ImmersiveMapSettings.RenderLoopSettings) {
        self.configuration = configuration
    }

    func updateConfiguration(_ configuration: ImmersiveMapSettings.RenderLoopSettings) {
        self.configuration = configuration
    }

    var shouldRenderFrame: Bool {
        configuration.forceContinuousRendering
            || pendingFrameReason != nil
            || activeReasons.isEmpty == false
    }

    var shouldPauseDisplayLink: Bool {
        shouldRenderFrame == false
    }

    var activeReasonDescription: String? {
        var reasons: [String] = []
        if configuration.forceContinuousRendering {
            reasons.append("force continuous rendering")
        }
        if let pendingFrameReason {
            reasons.append("pending frame: \(pendingFrameReason.description)")
        }
        reasons.append(contentsOf: Activity.allCases
            .filter { activeReasons.contains($0) }
            .map(\.rawValue))
        return reasons.isEmpty ? nil : reasons.joined(separator: ", ")
    }

    var preferredFramesPerSecond: Int {
        if configuration.forceContinuousRendering {
            return configuration.interactionFramesPerSecond
        }
        if activeReasons.contains(where: \.usesInteractionFrameRate) {
            return configuration.interactionFramesPerSecond
        }
        if activeReasons.contains(.labelFade) {
            return configuration.labelFadeFramesPerSecond
        }
        return 0
    }

    func requestFrame(reason: RenderInvalidationReason) {
        pendingFrameReason = reason
    }

    func setActivity(_ activity: Activity,
                     isActive: Bool) {
        if isActive {
            activeReasons.insert(activity)
        } else {
            activeReasons.remove(activity)
        }
    }

    func markFrameScheduled() {
        pendingFrameReason = nil
    }
}

private extension RenderInvalidationReason {
    var description: String {
        switch self {
        case .tileAvailable:
            return "tile available"
        case .externalStateChanged:
            return "external state changed"
        }
    }
}
