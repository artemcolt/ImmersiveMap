// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import QuartzCore

/// Composition root для runtime collaborators `ImmersiveMapUIView`.
/// Создает и владеет feature runtimes/controllers, затем отдает view прямые зависимости.
@MainActor
final class ImmersiveMapRuntimeGraph {
    let gestureController: MapGestureController
    let renderRuntime: ImmersiveMapRenderRuntime
    let viewportRuntime: ImmersiveMapViewportRuntime
    let avatarRuntime: ImmersiveMapAvatarRuntime
    let controlsRuntime: ImmersiveMapControlsRuntime
    let cameraRuntime: ImmersiveMapCameraRuntime
    let interactionRuntime: ImmersiveMapInteractionRuntime
    let cameraAnimationRuntime: ImmersiveMapCameraAnimationRuntime
    let cameraCommandHandler: ImmersiveMapCameraCommandHandler
    let selectionHandler: ImmersiveMapSelectionHandler
    let tapHandler: ImmersiveMapTapHandler
    let rendererBuilder: ImmersiveMapRendererBuilder
    let frameRenderDelegate: ImmersiveMapFrameRenderDelegate

    init(mapView: ImmersiveMapUIView,
         layer: CAMetalLayer,
         settings: ImmersiveMapSettings,
         initialCameraPosition: ImmersiveMapCameraPosition?) {
        let gestureController = MapGestureController(mapView: mapView)
        let renderRuntime = ImmersiveMapRenderRuntime(configuration: settings.renderLoop)
        let viewportRuntime = ImmersiveMapViewportRuntime()
        let avatarRuntime = ImmersiveMapAvatarRuntime()
        let controlsRuntime = ImmersiveMapControlsRuntime(mapView: mapView,
                                                          mapPanGesture: gestureController.panGesture,
                                                          settings: settings)
        let cameraRuntime = ImmersiveMapCameraRuntime(settings: settings,
                                                      initialCameraPosition: initialCameraPosition,
                                                      renderRuntime: renderRuntime,
                                                      controlsRuntime: controlsRuntime)
        let interactionRuntime = ImmersiveMapInteractionRuntime(cameraRuntime: cameraRuntime,
                                                                renderRuntime: renderRuntime)
        let cameraAnimationRuntime = ImmersiveMapCameraAnimationRuntime(cameraRuntime: cameraRuntime,
                                                                        interactionRuntime: interactionRuntime,
                                                                        renderRuntime: renderRuntime)
        let cameraCommandHandler = ImmersiveMapCameraCommandHandler(cameraRuntime: cameraRuntime,
                                                                    cameraAnimationRuntime: cameraAnimationRuntime)
        let selectionHandler = ImmersiveMapSelectionHandler(avatarRuntime: avatarRuntime,
                                                            viewportRuntime: viewportRuntime,
                                                            renderRuntime: renderRuntime)
        let tapHandler = ImmersiveMapTapHandler(controlsRuntime: controlsRuntime,
                                                selectionHandler: selectionHandler,
                                                cameraRuntime: cameraRuntime)
        let rendererBuilder = ImmersiveMapRendererBuilder(cameraRuntime: cameraRuntime,
                                                          avatarRuntime: avatarRuntime,
                                                          renderRuntime: renderRuntime,
                                                          selectionHandler: selectionHandler)
        let frameRenderDelegate = ImmersiveMapFrameRenderDelegate(layer: layer,
                                                                  renderRuntime: renderRuntime,
                                                                  viewportRuntime: viewportRuntime,
                                                                  cameraAnimationRuntime: cameraAnimationRuntime)

        self.gestureController = gestureController
        self.renderRuntime = renderRuntime
        self.viewportRuntime = viewportRuntime
        self.avatarRuntime = avatarRuntime
        self.controlsRuntime = controlsRuntime
        self.cameraRuntime = cameraRuntime
        self.interactionRuntime = interactionRuntime
        self.cameraAnimationRuntime = cameraAnimationRuntime
        self.cameraCommandHandler = cameraCommandHandler
        self.selectionHandler = selectionHandler
        self.tapHandler = tapHandler
        self.rendererBuilder = rendererBuilder
        self.frameRenderDelegate = frameRenderDelegate
    }
}

#endif
