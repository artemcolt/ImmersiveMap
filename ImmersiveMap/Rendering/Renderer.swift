// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import MetalKit
import QuartzCore

final class Renderer {
    private let cameraCoordinator: ImmersiveMapCameraCoordinator
    private let resources: RenderStaticResources
    private let frameEngine: RenderFrameEngine

    init(layer: CAMetalLayer,
         avatarsControllerProvider: @escaping () -> ImmersiveMapAvatarsController?,
         config: ImmersiveMapSettings = .default,
         cameraCoordinator: ImmersiveMapCameraCoordinator,
         events: RenderFrameEvents) {
        self.cameraCoordinator = cameraCoordinator
        self.resources = RenderStaticResources(layer: layer,
                                               avatarsControllerProvider: avatarsControllerProvider,
                                               config: config,
                                               onTileAvailable: { _ in
                                                   events.invalidate(.tileAvailable)
                                               })
        self.frameEngine = RenderFrameEngine(settings: config,
                                             resources: resources,
                                             cameraCoordinator: cameraCoordinator,
                                             events: events)
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
