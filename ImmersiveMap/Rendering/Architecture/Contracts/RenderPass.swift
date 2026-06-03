// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  RenderPass.swift
//  ImmersiveMap
//

import Foundation

enum RenderPass: String, CaseIterable {
    case scene
    case labels
    case avatars
    case debugOverlay
}

enum RenderSkipReason: String, CaseIterable, Hashable {
    case zeroDrawableSize
    case missingScreenMatrix
    case missingCameraState
    case inFlightSlotsExhausted
    case missingDrawable
    case missingCommandBuffer
    case flatTileOriginUnavailable
    case noLabelContent
    case noAvatarContent
    case debugOverlayDisabled
}

struct RenderPassAvailability {
    let labelsEnabled: Bool
    let avatarsEnabled: Bool
    let debugOverlayEnabled: Bool
}

struct RenderPassPlanItem {
    let pass: RenderPass
    let enabled: Bool
    let skipReason: RenderSkipReason?
}

struct RenderPassPlanner {
    static func plan(availability: RenderPassAvailability) -> [RenderPassPlanItem] {
        [
            RenderPassPlanItem(pass: .scene, enabled: true, skipReason: nil),
            RenderPassPlanItem(pass: .labels,
                               enabled: availability.labelsEnabled,
                               skipReason: availability.labelsEnabled ? nil : .noLabelContent),
            RenderPassPlanItem(pass: .avatars,
                               enabled: availability.avatarsEnabled,
                               skipReason: availability.avatarsEnabled ? nil : .noAvatarContent),
            RenderPassPlanItem(pass: .debugOverlay,
                               enabled: availability.debugOverlayEnabled,
                               skipReason: availability.debugOverlayEnabled ? nil : .debugOverlayDisabled)
        ]
    }
}
