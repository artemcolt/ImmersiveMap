// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import UIKit

@MainActor
final class ImmersiveMapDebugOverlayRuntime {
    private let hudView = DebugOverlayHUDView()

    init(mapView: ImmersiveMapUIView) {
        mapView.addSubview(hudView)
    }

    func layout(in bounds: CGRect) {
        hudView.frame = bounds
    }

    func apply(snapshot: DebugOverlayHUDSnapshot?) {
        hudView.apply(snapshot: snapshot)
    }

    func apply(settings: ImmersiveMapSettings.DebugSettings) {
        guard settings.overlayEnabled == false else { return }
        hudView.apply(snapshot: nil)
    }
}

#endif
