// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore
import UIKit

public class ImmersiveMapUIView: UIView {
    public override class var layerClass: AnyClass { return CAMetalLayer.self }

    // MARK: - Configuration

    var settings: ImmersiveMapSettings

    // MARK: - Rendering

    private var renderer: Renderer?
    private var memoryWarningObserver: NSObjectProtocol?

    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }

    // MARK: - Controllers

    private(set) var runtimeGraph: ImmersiveMapRuntimeGraph!
    var gestureController: MapGestureController { runtimeGraph.gestureController }
    var renderRuntime: ImmersiveMapRenderRuntime { runtimeGraph.renderRuntime }
    var viewportRuntime: ImmersiveMapViewportRuntime { runtimeGraph.viewportRuntime }
    var avatarRuntime: ImmersiveMapAvatarRuntime { runtimeGraph.avatarRuntime }
    var controlsRuntime: ImmersiveMapControlsRuntime { runtimeGraph.controlsRuntime }
    var cameraRuntime: ImmersiveMapCameraRuntime { runtimeGraph.cameraRuntime }
    var cameraCommandHandler: ImmersiveMapCameraCommandHandler { runtimeGraph.cameraCommandHandler }
    var interactionRuntime: ImmersiveMapInteractionRuntime { runtimeGraph.interactionRuntime }
    var cameraAnimationRuntime: ImmersiveMapCameraAnimationRuntime { runtimeGraph.cameraAnimationRuntime }
    var selectionHandler: ImmersiveMapSelectionHandler { runtimeGraph.selectionHandler }
    var tapHandler: ImmersiveMapTapHandler { runtimeGraph.tapHandler }
    var rendererBuilder: ImmersiveMapRendererBuilder { runtimeGraph.rendererBuilder }

    // MARK: - Initialization

    override init(frame: CGRect) {
        self.settings = .default
        super.init(frame: frame)
        setup(initialCameraPosition: nil)
    }

    required init?(coder: NSCoder) {
        self.settings = .default
        super.init(coder: coder)
        setup(initialCameraPosition: nil)
    }

    public convenience init(frame: CGRect,
                            settings: ImmersiveMapSettings,
                            avatarsController: ImmersiveMapAvatarsController? = nil,
                            cameraPosition: ImmersiveMapCameraPosition? = nil) {
        self.init(frame: frame,
                  settings: settings,
                  avatarsController: avatarsController,
                  cameraPosition: cameraPosition,
                  cameraController: nil,
                  selectionController: nil)
    }

    init(frame: CGRect,
         settings: ImmersiveMapSettings,
         avatarsController: ImmersiveMapAvatarsController?,
         cameraPosition: ImmersiveMapCameraPosition?,
         cameraController: ImmersiveMapCameraController?,
         selectionController: ImmersiveMapSelectionController?) {
        self.settings = settings
        super.init(frame: frame)
        setup(initialCameraPosition: cameraPosition)
        syncControllers(avatarsController: avatarsController,
                        cameraController: cameraController,
                        selectionController: selectionController)
    }

    private func setup(initialCameraPosition: ImmersiveMapCameraPosition?) {
        metalLayer.contentsScale = UIScreen.main.scale
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderer?.handleMemoryWarning()
        }

        runtimeGraph = ImmersiveMapRuntimeGraph(mapView: self,
                                                layer: metalLayer,
                                                settings: settings,
                                                initialCameraPosition: initialCameraPosition)

        createRenderer(settings: settings,
                       cameraPosition: initialCameraPosition)
        cameraRuntime.syncPitchControlValue()

        renderRuntime.start(frameDelegate: runtimeGraph.frameRenderDelegate)
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let didChangeDrawableSize = viewportRuntime.layout(layer: metalLayer,
                                                           bounds: bounds,
                                                           contentsScale: metalLayer.contentsScale)
        if didChangeDrawableSize {
            requestFrame()
        }

        controlsRuntime.layout(in: bounds,
                               safeAreaInsets: safeAreaInsets)
    }

    // MARK: - Updates

    /// Синхронизирует новые параметры из SwiftUI `updateUIView` с уже созданным UIKit/Metal view.
    func update(settings: ImmersiveMapSettings,
                avatarsController: ImmersiveMapAvatarsController?,
                cameraController: ImmersiveMapCameraController?,
                selectionController: ImmersiveMapSelectionController?,
                cameraPosition: ImmersiveMapCameraPosition?) {
        applySettings(settings)
        syncControllers(avatarsController: avatarsController,
                        cameraController: cameraController,
                        selectionController: selectionController)
        cameraCommandHandler.applyCameraPosition(cameraPosition)
    }

    func dismantle() {
        syncControllers(avatarsController: nil,
                        cameraController: nil,
                        selectionController: nil)
    }

    /// Применяет новые SwiftUI-настройки к runtime карты и через planner выбирает:
    /// обновить существующий renderer на лету или пересоздать его для изменений,
    /// которые затрагивают кэши, подготовленные данные или GPU-ресурсы.
    private func applySettings(_ settings: ImmersiveMapSettings) {
        guard self.settings != settings else {
            return
        }

        let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: self.settings, to: settings)
        self.settings = settings
        cameraRuntime.updateSettings(settings)
        cameraAnimationRuntime.updateSettings()
        controlsRuntime.applyAttributionSettings(settings.attribution)
        setNeedsLayout()
        renderRuntime.updateRenderLoopSettings(settings.renderLoop)
        if plan.requiresRendererRecreation {
            recreateRenderer(with: settings)
        } else {
            renderer?.applySettings(settings)
        }

        cameraRuntime.syncPitchControlValue()
        requestFrame()
    }

    func requestFrame() {
        renderRuntime.requestFrame()
    }

    // MARK: - Controller Sync

    @MainActor
    private func syncControllers(avatarsController newAvatarsController: ImmersiveMapAvatarsController?,
                         cameraController newCameraController: ImmersiveMapCameraController?,
                         selectionController newSelectionController: ImmersiveMapSelectionController?) {
        let shouldUpdateAvatarsController = avatarRuntime.isAttachedController(newAvatarsController) == false
        let shouldUpdateCameraController = cameraRuntime.isAttachedController(newCameraController) == false
        guard shouldUpdateAvatarsController
            || shouldUpdateCameraController else {
            selectionHandler.syncController(newSelectionController)
            return
        }

        if shouldUpdateAvatarsController {
            avatarRuntime.attachController(newAvatarsController,
                                           selectionHandler: selectionHandler,
                                           renderRuntime: renderRuntime)
        }
        if shouldUpdateCameraController {
            cameraRuntime.attachController(newCameraController,
                                           commandHandler: cameraCommandHandler)
        }
        selectionHandler.syncController(newSelectionController)
    }

    // MARK: - Renderer

    private func createRenderer(settings: ImmersiveMapSettings,
                                cameraPosition: ImmersiveMapCameraPosition?) {
        let renderer = rendererBuilder.makeRenderer(layer: metalLayer,
                                                    settings: settings,
                                                    cameraPosition: cameraPosition)
        self.renderer = renderer
        renderRuntime.attachRenderer(renderer)
        avatarRuntime.markSnapshotDirty()
        requestFrame()
    }

    private func recreateRenderer(with settings: ImmersiveMapSettings) {
        cameraAnimationRuntime.cancelAnimations(notifyFlightCompletion: false)
        let cameraPosition = cameraRuntime.cameraPositionForRendererRecreation()
        renderRuntime.detachRenderer()
        renderer = nil
        cameraRuntime.clearCoordinator()
        createRenderer(settings: settings,
                       cameraPosition: cameraPosition)
    }

    // MARK: - Cleanup

    deinit {
        cameraAnimationRuntime.reset()
        let detachedAvatarRuntime = avatarRuntime
        Task { @MainActor in
            detachedAvatarRuntime.detachController()
        }
        cameraRuntime.detachController()
        let detachedSelectionHandler = selectionHandler
        Task { @MainActor in
            detachedSelectionHandler.syncController(nil)
        }
        renderRuntime.stop()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }
}
