// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore

enum RenderFrameStageMeasurer {
    static func measure(_ stage: FrameStage,
                        diagnostics: FrameDiagnostics,
                        block: () -> Void) {
        let start = CACurrentMediaTime()
        block()
        diagnostics.recordStage(stage, duration: CACurrentMediaTime() - start)
    }
}

enum RenderDebugOverlayPolicy {
    static func shouldEncode(_ settings: ImmersiveMapSettings.DebugSettings) -> Bool {
        guard settings.overlayEnabled || settings.tileOverlayEnabled else {
            return false
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

enum RenderFrameClearColor {
    static func make(transition: Float,
                     settings: ImmersiveMapSettings) -> MTLClearColor {
        let transitionMix = Double(transition)
        let spaceColor = settings.scene.space.clearColor
        let mapColor = settings.scene.mapClearColor
        let clearColorValue = spaceColor + (mapColor - spaceColor) * transitionMix

        return MTLClearColor(red: clearColorValue.x,
                             green: clearColorValue.y,
                             blue: clearColorValue.z,
                             alpha: clearColorValue.w)
    }
}
