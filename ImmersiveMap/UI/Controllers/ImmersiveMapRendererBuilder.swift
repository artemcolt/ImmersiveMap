// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import QuartzCore

/// Собирает `RenderFrameEngine` из текущего runtime graph.
/// Создает render camera и связывает renderer dependencies, не раскрывая детали сборки во view.
final class ImmersiveMapRendererBuilder {
    private let cameraRuntime: ImmersiveMapCameraRuntime
    private let avatarRuntime: ImmersiveMapAvatarRuntime
    private let renderRuntime: ImmersiveMapRenderRuntime
    private let selectionHandler: ImmersiveMapSelectionHandler
    private let debugOverlayRuntime: ImmersiveMapDebugOverlayRuntime
    private let debugOverlayControls: DebugOverlayControlState
    private let tileTraceRecorder: TileTraceRecorder

    init(cameraRuntime: ImmersiveMapCameraRuntime,
         avatarRuntime: ImmersiveMapAvatarRuntime,
         renderRuntime: ImmersiveMapRenderRuntime,
         selectionHandler: ImmersiveMapSelectionHandler,
         debugOverlayRuntime: ImmersiveMapDebugOverlayRuntime,
         debugOverlayControls: DebugOverlayControlState,
         tileTraceRecorder: TileTraceRecorder) {
        self.cameraRuntime = cameraRuntime
        self.avatarRuntime = avatarRuntime
        self.renderRuntime = renderRuntime
        self.selectionHandler = selectionHandler
        self.debugOverlayRuntime = debugOverlayRuntime
        self.debugOverlayControls = debugOverlayControls
        self.tileTraceRecorder = tileTraceRecorder
    }

    func makeRenderer(layer: CAMetalLayer,
                      settings: ImmersiveMapSettings,
                      cameraPosition: ImmersiveMapCameraPosition?) -> RenderFrameEngine {
        let renderCamera = cameraRuntime.makeRenderCamera(settings: settings,
                                                          cameraPosition: cameraPosition)
        let eventSink = ImmersiveMapRenderEventSink(renderRuntime: renderRuntime,
                                                    selectionHandler: selectionHandler,
                                                    debugOverlayRuntime: debugOverlayRuntime)
        let providerRuntime = ImmersiveMapProviderRuntimeContext(settings: settings)
        return RenderFrameEngine(layer: layer,
                                 avatarSource: avatarRuntime,
                                 providerRuntime: providerRuntime,
                                 settings: settings,
                                 debugOverlayControls: debugOverlayControls,
                                 renderCamera: renderCamera,
                                 presentationStateResolver: cameraRuntime.presentationStateResolver,
                                 eventSink: eventSink,
                                 tileTraceRecorder: tileTraceRecorder)
    }
}

#endif
