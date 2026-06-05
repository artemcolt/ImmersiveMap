// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

protocol RenderPassAvailabilityProvider: AnyObject {
    func contributePassAvailability(settings: ImmersiveMapSettings,
                                    builder: inout RenderPassAvailabilityBuilder)
}

struct RenderPassAvailabilityBuilder {
    var labelsEnabled: Bool = false
    var avatarsEnabled: Bool = false
    var debugOverlayEnabled: Bool = false

    func build() -> RenderPassAvailability {
        RenderPassAvailability(labelsEnabled: labelsEnabled,
                               avatarsEnabled: avatarsEnabled,
                               debugOverlayEnabled: debugOverlayEnabled)
    }
}
