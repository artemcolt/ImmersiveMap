// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import UIKit

@MainActor
final class ImmersiveMapDebugOverlayRuntime {
    private let hudView = DebugOverlayHUDView()
    private let controls: DebugOverlayControlState
    private weak var renderRuntime: ImmersiveMapRenderRuntime?

    init(mapView: ImmersiveMapUIView,
         controls: DebugOverlayControlState,
         renderRuntime: ImmersiveMapRenderRuntime) {
        self.controls = controls
        self.renderRuntime = renderRuntime
        hudView.onAxesEnabledChanged = { [weak controls, weak renderRuntime] isEnabled in
            controls?.setAxesEnabled(isEnabled)
            renderRuntime?.requestFrame(reason: .externalStateChanged)
        }
        hudView.onTileLayersEnabledChanged = { [weak controls, weak renderRuntime] isEnabled in
            controls?.setTileLayersEnabled(isEnabled)
            renderRuntime?.requestFrame(reason: .externalStateChanged)
        }
        mapView.addSubview(hudView)
    }

    func layout(in bounds: CGRect) {
        hudView.frame = bounds
    }

    func apply(snapshot: DebugOverlayHUDSnapshot?) {
        hudView.apply(snapshot: snapshot)
    }

    func apply(settings: ImmersiveMapSettings.DebugSettings) {
        hudView.apply(isDebugPanelEnabled: settings.enableDebugPanel,
                      controls: controls.snapshot())
        if settings.enableDebugPanel == false {
            hudView.apply(snapshot: nil)
        }
    }
}

#endif
