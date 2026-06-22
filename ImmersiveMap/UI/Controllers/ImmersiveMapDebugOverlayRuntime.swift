// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import UIKit

@MainActor
final class ImmersiveMapDebugOverlayRuntime {
    private let hudView = DebugOverlayHUDView()
    private let controls: DebugOverlayControlState
    private let tileTraceRecorder: TileTraceRecorder
    private weak var renderRuntime: ImmersiveMapRenderRuntime?

    init(mapView: ImmersiveMapUIView,
         controls: DebugOverlayControlState,
         tileTraceRecorder: TileTraceRecorder,
         renderRuntime: ImmersiveMapRenderRuntime,
         cameraRuntime: ImmersiveMapCameraRuntime,
         cameraAnimationRuntime: ImmersiveMapCameraAnimationRuntime) {
        self.controls = controls
        self.tileTraceRecorder = tileTraceRecorder
        self.renderRuntime = renderRuntime
        hudView.onAxesEnabledChanged = { [weak controls, weak renderRuntime] isEnabled in
            controls?.setAxesEnabled(isEnabled)
            renderRuntime?.requestFrame(reason: .externalStateChanged)
        }
        hudView.onTileLayersEnabledChanged = { [weak controls, weak renderRuntime] isEnabled in
            controls?.setTileLayersEnabled(isEnabled)
            renderRuntime?.requestFrame(reason: .externalStateChanged)
        }
        hudView.onWireframeEnabledChanged = { [weak controls, weak renderRuntime] isEnabled in
            controls?.setWireframeEnabled(isEnabled)
            renderRuntime?.requestFrame(reason: .externalStateChanged)
        }
        hudView.onEarthSceneEnabledChanged = { [weak mapView] isEnabled in
            mapView?.setEarthSceneEnabledFromDebugOverlay(isEnabled)
        }
        hudView.onSurfaceModeSwitchRequested = { [weak cameraRuntime, weak cameraAnimationRuntime] in
            cameraAnimationRuntime?.cancelAnimations()
            cameraRuntime?.switchRenderMode()
        }
        hudView.onTileTraceRecordingToggle = { [weak self, weak renderRuntime] in
            guard let self else { return }
            if tileTraceRecorder.snapshot().isRecording {
                tileTraceRecorder.stopRecording()
            } else {
                _ = tileTraceRecorder.startRecording()
            }
            hudView.apply(tileTraceSnapshot: tileTraceRecorder.snapshot())
            renderRuntime?.requestFrame(reason: .externalStateChanged)
        }
        hudView.apply(tileTraceSnapshot: tileTraceRecorder.snapshot())
        mapView.addSubview(hudView)
    }

    func layout(in bounds: CGRect) {
        hudView.frame = bounds
    }

    func apply(snapshot: DebugOverlayHUDSnapshot?) {
        hudView.apply(snapshot: snapshot)
    }

    func apply(settings: ImmersiveMapSettings) {
        hudView.apply(isDebugPanelEnabled: settings.debug.enableDebugPanel,
                      controls: controls.snapshot(),
                      earthSceneEnabled: settings.scene.earth.isEnabled)
        hudView.apply(tileTraceSnapshot: tileTraceRecorder.snapshot())
        if settings.debug.enableDebugPanel == false {
            hudView.apply(snapshot: nil)
        }
    }
}

#endif
