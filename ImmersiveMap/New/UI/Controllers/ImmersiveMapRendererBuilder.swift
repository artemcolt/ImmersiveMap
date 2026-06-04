// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import QuartzCore

/// Собирает `Renderer` из текущего runtime graph.
/// Создает camera coordinator и связывает renderer dependencies, не раскрывая детали сборки во view.
final class ImmersiveMapRendererBuilder {
    private let cameraRuntime: ImmersiveMapCameraRuntime
    private let avatarRuntime: ImmersiveMapAvatarRuntime
    private let renderRuntime: ImmersiveMapRenderRuntime
    private let selectionHandler: ImmersiveMapSelectionHandler

    init(cameraRuntime: ImmersiveMapCameraRuntime,
         avatarRuntime: ImmersiveMapAvatarRuntime,
         renderRuntime: ImmersiveMapRenderRuntime,
         selectionHandler: ImmersiveMapSelectionHandler) {
        self.cameraRuntime = cameraRuntime
        self.avatarRuntime = avatarRuntime
        self.renderRuntime = renderRuntime
        self.selectionHandler = selectionHandler
    }

    func makeRenderer(layer: CAMetalLayer,
                      settings: ImmersiveMapSettings,
                      cameraPosition: ImmersiveMapCameraPosition?) -> Renderer {
        let cameraCoordinator = cameraRuntime.makeCoordinator(settings: settings,
                                                              cameraPosition: cameraPosition)
        let eventSink = ImmersiveMapRenderEventSink(renderRuntime: renderRuntime,
                                                    selectionHandler: selectionHandler)
        return Renderer(layer: layer,
                        avatarSource: avatarRuntime,
                        config: settings,
                        cameraCoordinator: cameraCoordinator,
                        eventSink: eventSink)
    }
}
