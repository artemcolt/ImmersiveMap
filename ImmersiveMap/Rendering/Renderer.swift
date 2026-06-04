// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import MetalKit
import QuartzCore

final class Renderer {
    private let cameraCoordinator: ImmersiveMapCameraCoordinator
    private let resources: RenderStaticResources
    private let frameEngine: RenderFrameEngine

    init(layer: CAMetalLayer,
         avatarSource: AvatarRenderSource,
         config: ImmersiveMapSettings = .default,
         cameraCoordinator: ImmersiveMapCameraCoordinator,
         eventSink: RenderFrameEventSink) {
        self.cameraCoordinator = cameraCoordinator
        self.resources = RenderStaticResources(layer: layer,
                                               avatarSource: avatarSource,
                                               config: config,
                                               eventSink: eventSink)
        self.frameEngine = RenderFrameEngine(settings: config,
                                             resources: resources,
                                             cameraCoordinator: cameraCoordinator,
                                             eventSink: eventSink)
    }

    @discardableResult
    func render(to layer: CAMetalLayer) -> Bool {
        frameEngine.render(to: layer)
    }

    func applySettings(_ settings: ImmersiveMapSettings) {
        cameraCoordinator.applySettings(settings)
        resources.applySettings(settings)
        frameEngine.applySettings(settings)
    }

    func handleMemoryWarning() {
        frameEngine.handleMemoryWarning()
    }
}
