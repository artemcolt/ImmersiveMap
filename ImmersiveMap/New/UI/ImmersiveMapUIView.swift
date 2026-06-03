// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore
import UIKit

public class ImmersiveMapUIView: UIView, UIGestureRecognizerDelegate {
    private static let attributionBadgeInset: CGFloat = 12

    public override class var layerClass: AnyClass { return CAMetalLayer.self }

    var settings: ImmersiveMapSettings
    let initialCameraPosition: ImmersiveMapCameraPosition?
    private weak var avatarsController: ImmersiveMapAvatarsController?

    override init(frame: CGRect) {
        self.settings = .default
        self.initialCameraPosition = nil
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        self.settings = .default
        self.initialCameraPosition = nil
        super.init(coder: coder)
        setup()
    }

    public init(frame: CGRect,
                settings: ImmersiveMapSettings,
                avatarsController: ImmersiveMapAvatarsController? = nil,
                cameraPosition: ImmersiveMapCameraPosition? = nil) {
        self.settings = settings
        self.initialCameraPosition = cameraPosition
        super.init(frame: frame)
        setup()
        syncControllers(avatarsController: avatarsController,
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
        self.initialCameraPosition = cameraPosition
        super.init(frame: frame)
        setup()
        syncControllers(avatarsController: avatarsController,
                        cameraController: cameraController,
                        selectionController: selectionController)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds  // Ensure the layer follows the view bounds

        let scale = metalLayer.contentsScale
        let width = bounds.width * scale
        let height = bounds.height * scale
        let newDrawableSize = CGSize(width: width, height: height)

        if metalLayer.drawableSize != newDrawableSize {
            metalLayer.drawableSize = newDrawableSize  // Manually update drawableSize on each layout
            requestFrame()
        }

        pitchControlZone.layout(in: bounds)
        zoomControlZone.layout(in: bounds)

        let badgeAvailableWidth = max(0, bounds.width - safeAreaInsets.left - safeAreaInsets.right - Self.attributionBadgeInset * 2)
        let badgeSize = attributionBadge.sizeThatFits(CGSize(width: badgeAvailableWidth,
                                                             height: bounds.height))
        attributionBadge.frame = CGRect(
            x: bounds.width - safeAreaInsets.right - Self.attributionBadgeInset - badgeSize.width,
            y: bounds.height - safeAreaInsets.bottom - Self.attributionBadgeInset - badgeSize.height,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }

    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }

    var mapPanGesture: UIPanGestureRecognizer!
    private var mapTapGesture: UITapGestureRecognizer!
    private var pitchControlZone: PitchControlZone!
    private var zoomControlZone: ZoomControlZone!
    private var attributionBadge: AttributionBadgeView!
    var cameraCoordinator: ImmersiveMapCameraCoordinator?
    var appliedCameraPosition: ImmersiveMapCameraPosition?
    private var memoryWarningObserver: NSObjectProtocol?
    lazy var mapRenderLoop = ImmersiveMapRenderLoop(configuration: settings.renderLoop,
                                                   layerProvider: { [weak self] in
                                                       self?.metalLayer
                                                   },
                                                   isSurfaceRenderable: { [weak self] in
                                                       guard let self else { return false }
                                                       return self.bounds.width > 0 && self.bounds.height > 0
                                                   },
                                                   prepareFrame: { [weak self] currentTime in
                                                       self?.prepareRenderLoopFrame(currentTime: currentTime)
                                                   })
    private lazy var globeCameraPanInertia = GlobeCameraPanInertia(configuration: makeGlobeCameraPanInertiaConfiguration())
    private var globeCameraPanInertiaIsActive = false
    let cameraFlightAnimator = CameraFlightAnimator()
    private var cameraFlightTargetPosition: ImmersiveMapCameraPosition?
    private var cameraFlightCompletion: ((Bool) -> Void)?
    var panInteractionActive: Bool = false
    private var pinchInteractionActive: Bool = false
    private var rotationInteractionActive: Bool = false
    var pitchInteractionActive: Bool = false
    var zoomControlInteractionActive: Bool = false
    var scrollZoomInteractionActive: Bool = false
    weak var cameraController: ImmersiveMapCameraController?
    private weak var selectionController: ImmersiveMapSelectionController?
    private var currentSelection: ImmersiveMapSelection?
    var avatarSelectionSnapshot: AvatarSelectionSnapshot = .empty
    private var anchoredAvatarMarkerID: UInt64?
    private var anchoredAvatarVerticalScreenOffsetFraction: CGFloat = 0
    private var lastAnchoredAvatarCoordinate: GeoCoordinate?

    private func setup() {
        metalLayer.contentsScale = UIScreen.main.scale
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.mapRenderLoop.handleMemoryWarning()
        }

        // Add one-finger pan gesture recognizer
        mapPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        mapPanGesture.delegate = self
        mapPanGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(mapPanGesture)

        mapTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        mapTapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(mapTapGesture)

        // Add two-finger rotation gesture recognizer
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture.delegate = self
        addGestureRecognizer(rotationGesture)

        // Add two-finger pinch zoom gesture recognizer
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        addGestureRecognizer(pinchGesture)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        mapTapGesture.require(toFail: doubleTap)

        pitchControlZone = PitchControlZone(mapView: self,
                                            mapPanGesture: mapPanGesture)
        zoomControlZone = ZoomControlZone(mapView: self,
                                          mapPanGesture: mapPanGesture)

        attributionBadge = AttributionBadgeView()
        attributionBadge.apply(settings.attribution)
        addSubview(attributionBadge)

        createRenderer(settings: settings,
                       cameraPosition: initialCameraPosition)
        syncPitchControlValue()

        mapRenderLoop.start()
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous rotation and pinch recognition
        if (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) ||
           (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) {
            return true
        }
        return false
    }

    @objc private func handleDoubleTap(_ gestrue: UITapGestureRecognizer) {
        _ = gestrue.location(in: self)
        // Double tap toggles between automatic projection and a temporary opposite-backend override.
        cancelCameraAnimations()
        cameraCoordinator?.switchRenderMode()
        syncPitchControlValue()
        requestFrame()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        handleMapTap(at: gesture.location(in: self))
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let cameraCoordinator else { return }
        updateInteractionState(for: gesture.state, gestureKind: .rotation)
        let rotation = gesture.rotation
        cameraCoordinator.rotateCameraYaw(delta: Float(rotation) * settings.camera.rotationGestureSensitivity)
        notifyCameraPositionChanged()
        // Reset rotation to accumulate changes
        gesture.rotation = 0
        requestFrame()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let cameraCoordinator else { return }
        updateInteractionState(for: gesture.state, gestureKind: .pan)

        let translation = gesture.translation(in: self)
        cameraCoordinator.panCamera(deltaX: Double(translation.x) * settings.camera.gesturePanTranslationScale,
                                    deltaY: Double(translation.y) * settings.camera.gesturePanTranslationScale)
        notifyCameraPositionChanged()

        // Reset translation to accumulate changes
        gesture.setTranslation(.zero, in: self)

        // Redraw view after panning
        requestFrame()

        switch gesture.state {
        case .ended:
            startGlobeCameraPanInertiaIfNeeded(initialVelocity: gesture.velocity(in: self))
        case .cancelled, .failed:
            cancelGlobeCameraPanInertia()
        case .began, .changed, .possible:
            break
        @unknown default:
            cancelGlobeCameraPanInertia()
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let cameraCoordinator else { return }
        updateInteractionState(for: gesture.state, gestureKind: .pinch)

        let scale = gesture.scale
        cameraCoordinator.zoomCamera(scale: scale, velocity: gesture.velocity)
        notifyCameraPositionChanged()
        gesture.scale = 1.0
        syncPitchControlValue()
        requestFrame()
    }

    private func prepareRenderLoopFrame(currentTime: CFTimeInterval) {
        advanceGlobeCameraPanInertiaIfNeeded(currentTime: currentTime)
        advanceCameraFlightIfNeeded(currentTime: currentTime)
        syncAnchoredCameraToMarkerIfNeeded()
    }

    public func fly(to cameraPosition: ImmersiveMapCameraPosition,
                    options: CameraFlightOptions = .default,
                    completion: ((Bool) -> Void)? = nil) {
        startCameraFlight(to: cameraPosition,
                          options: options,
                          completion: completion,
                          currentTime: CACurrentMediaTime())
    }

    public func cancelFlight() {
        cancelCameraFlight()
    }

    public func setCameraPosition(_ cameraPosition: ImmersiveMapCameraPosition?) {
        guard appliedCameraPosition != cameraPosition else {
            return
        }

        cancelCameraAnimations()
        appliedCameraPosition = cameraPosition
        guard let cameraPosition else {
            return
        }

        cameraCoordinator?.setCameraPosition(cameraPosition)
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        requestFrame()
    }

    public func currentCameraPosition() -> ImmersiveMapCameraPosition? {
        cameraCoordinator?.currentCameraPosition() ?? appliedCameraPosition ?? initialCameraPosition
    }

    public func anchorCamera(toAvatarMarkerWithID markerID: UInt64) {
        anchorCamera(toAvatarMarkerWithID: markerID,
                     verticalScreenOffsetFraction: 0)
    }

    public func anchorCamera(toAvatarMarkerWithID markerID: UInt64,
                             verticalScreenOffsetFraction: CGFloat) {
        anchoredAvatarMarkerID = markerID
        anchoredAvatarVerticalScreenOffsetFraction = max(0, verticalScreenOffsetFraction)
        syncAnchoredCameraToMarkerIfNeeded()
        requestFrame()
    }

    public func stopAnchoringCamera() {
        anchoredAvatarMarkerID = nil
        anchoredAvatarVerticalScreenOffsetFraction = 0
        lastAnchoredAvatarCoordinate = nil
    }

    func update(settings: ImmersiveMapSettings,
                avatarsController: ImmersiveMapAvatarsController?,
                cameraController: ImmersiveMapCameraController?,
                selectionController: ImmersiveMapSelectionController?,
                cameraPosition: ImmersiveMapCameraPosition?) {
        applySettings(settings)
        syncControllers(avatarsController: avatarsController,
                        cameraController: cameraController,
                        selectionController: selectionController)
        setCameraPosition(cameraPosition)
    }

    func dismantle() {
        syncControllers(avatarsController: nil,
                        cameraController: nil,
                        selectionController: nil)
    }

    func applySettings(_ settings: ImmersiveMapSettings) {
        guard self.settings != settings else {
            return
        }

        let plan = ImmersiveMapSettings.makeApplicationPlan(from: self.settings, to: settings)
        self.settings = settings
        globeCameraPanInertiaIsActive = globeCameraPanInertia.updateConfiguration(makeGlobeCameraPanInertiaConfiguration())
        refreshCameraAnimationRenderingState()
        attributionBadge.apply(settings.attribution)
        setNeedsLayout()
        mapRenderLoop.updateConfiguration(settings.renderLoop)
        if plan.requiresRendererRecreation {
            recreateRenderer(with: settings)
        } else {
            mapRenderLoop.applyRendererSettings(settings)
        }

        syncPitchControlValue()
        requestFrame()
    }

    func requestFrame() {
        mapRenderLoop.invalidate(reason: .externalStateChanged)
    }

    func setLabelFadeRenderingActive(_ isActive: Bool) {
        mapRenderLoop.setLabelFadeRenderingActive(isActive)
    }

    func setBaseLabelFadeRenderingActive(_ isActive: Bool) {
        setLabelFadeRenderingActive(isActive)
    }

    func setLabelVisibilityCycleRenderingActive(_ isActive: Bool) {
        mapRenderLoop.setLabelVisibilityCycleRenderingActive(isActive)
    }

    func setCameraAnimationRenderingActive(_ isActive: Bool) {
        mapRenderLoop.setCameraAnimationRenderingActive(isActive)
    }

    func setAvatarAnimationRenderingActive(_ isActive: Bool) {
        mapRenderLoop.setAvatarAnimationRenderingActive(isActive)
    }

    private func refreshCameraAnimationRenderingState() {
        setCameraAnimationRenderingActive(globeCameraPanInertiaIsActive || cameraFlightAnimator.isActive)
    }

    func startCameraFlight(to cameraPosition: ImmersiveMapCameraPosition,
                                   options: CameraFlightOptions,
                                   completion: ((Bool) -> Void)?,
                                   currentTime: CFTimeInterval) {
        guard let cameraCoordinator else {
            completion?(false)
            return
        }

        cancelCameraAnimations()
        let startState = cameraCoordinator.currentCameraState()
        let targetState = ImmersiveMapCameraState(cameraPosition: cameraPosition,
                                         cameraSettings: settings.camera)
        if CameraFlightMath.hasMeaningfulDelta(from: startState, to: targetState) == false || options.duration <= 0 {
            appliedCameraPosition = cameraPosition
            cameraCoordinator.setCameraPosition(cameraPosition)
            syncPitchControlValue(fallbackCameraPosition: cameraPosition)
            notifyCameraPositionChanged()
            requestFrame()
            completion?(true)
            return
        }

        let resolvedRouteStyle = resolveCameraFlightRouteStyle(options.routeStyle,
                                                               startState: startState,
                                                               targetState: targetState)
        let didStart = cameraFlightAnimator.start(from: startState,
                                                    to: targetState,
                                                    duration: options.duration,
                                                    routeStyle: resolvedRouteStyle,
                                                    altitudeStyle: options.altitudeStyle,
                                                    currentTime: currentTime)
        guard didStart else {
            appliedCameraPosition = cameraPosition
            cameraCoordinator.setCameraPosition(cameraPosition)
            syncPitchControlValue(fallbackCameraPosition: cameraPosition)
            notifyCameraPositionChanged()
            requestFrame()
            completion?(true)
            return
        }

        cameraFlightTargetPosition = cameraPosition
        cameraFlightCompletion = completion
        refreshCameraAnimationRenderingState()
        requestFrame()
    }

    private func resolveCameraFlightRouteStyle(_ routeStyle: CameraFlightRouteStyle,
                                               startState: ImmersiveMapCameraState,
                                               targetState: ImmersiveMapCameraState) -> CameraFlightAnimator.ResolvedRouteStyle {
        switch routeStyle {
        case .mercatorShortestPath:
            return .mercatorShortestPath
        case .greatCircle:
            return .greatCircle
        case .automatic:
            guard let cameraCoordinator else {
                return .mercatorShortestPath
            }

            let automaticTransitionStartZoom = settings.presentation.automaticTransitionStartZoom
            let useGreatCircle = cameraCoordinator.isSphericalRenderBackendActive()
                || min(startState.zoom, targetState.zoom) < automaticTransitionStartZoom
            return useGreatCircle ? .greatCircle : .mercatorShortestPath
        }
    }

    private func finishCameraFlight(success: Bool) {
        let completion = cameraFlightCompletion
        cameraFlightCompletion = nil
        cameraFlightTargetPosition = nil
        refreshCameraAnimationRenderingState()
        completion?(success)
    }

    private func cancelCameraFlight(notifyCompletion: Bool = true) {
        guard cameraFlightAnimator.isActive || cameraFlightCompletion != nil else {
            refreshCameraAnimationRenderingState()
            return
        }

        cameraFlightAnimator.cancel()
        if notifyCompletion {
            finishCameraFlight(success: false)
        } else {
            cameraFlightCompletion = nil
            cameraFlightTargetPosition = nil
            refreshCameraAnimationRenderingState()
        }
    }

    func cancelCameraAnimations(notifyFlightCompletion: Bool = true) {
        cancelGlobeCameraPanInertia()
        cancelCameraFlight(notifyCompletion: notifyFlightCompletion)
    }

    private enum InteractionGestureKind {
        case pan
        case pinch
        case rotation
    }

    private func updateInteractionState(for state: UIGestureRecognizer.State,
                                        gestureKind: InteractionGestureKind) {
        let wasInteracting = hasActiveUserInteraction
        let isActive: Bool
        switch state {
        case .began, .changed:
            isActive = true
        case .ended, .cancelled, .failed:
            isActive = false
        case .possible:
            return
        @unknown default:
            isActive = false
        }

        if isActive && !wasInteracting {
            cameraController?.notifyUserInteractionBegan()
        }

        if isActive {
            cancelCameraAnimations()
        }

        switch gestureKind {
        case .pan:
            panInteractionActive = isActive
        case .pinch:
            pinchInteractionActive = isActive
        case .rotation:
            rotationInteractionActive = isActive
        }

        updateCombinedInteractionRenderingState()
    }

    func updateCombinedInteractionRenderingState() {
        mapRenderLoop.setInteractionRenderingActive(hasActiveUserInteraction)
    }

    @MainActor
    func syncControllers(avatarsController newAvatarsController: ImmersiveMapAvatarsController?,
                         cameraController newCameraController: ImmersiveMapCameraController?,
                         selectionController newSelectionController: ImmersiveMapSelectionController?) {
        let shouldUpdateAvatarsController = avatarsController !== newAvatarsController
        let shouldUpdateCameraController = cameraController !== newCameraController
        let shouldUpdateSelectionController = selectionController !== newSelectionController
        guard shouldUpdateAvatarsController
            || shouldUpdateCameraController
            || shouldUpdateSelectionController else {
            return
        }

        if shouldUpdateAvatarsController {
            avatarsController?.setChangeHandler(nil)
            avatarsController = newAvatarsController
            newAvatarsController?.setChangeHandler { [weak self] in
                self?.handleAvatarControllerDidChange()
            }
            newAvatarsController?.markSnapshotDirty()
            syncSelectionWithAvailableMapObjects()
            requestFrame()
        }
        if shouldUpdateCameraController {
            cameraController?.setCommandHandler(nil)
            cameraController?.updateCurrentCameraPosition(nil)
            cameraController = newCameraController
            newCameraController?.setCommandHandler { [weak self] command in
                self?.handleCameraCommand(command)
            }
            newCameraController?.updateCurrentCameraPosition(currentCameraPosition())
            notifyCameraPositionChanged()
        }
        if shouldUpdateSelectionController {
            selectionController?.setCommandHandler(nil)
            selectionController?.updateCurrentSelection(nil)
            selectionController = newSelectionController
            newSelectionController?.setCommandHandler { [weak self] command in
                self?.handleSelectionCommand(command) ?? false
            }
            newSelectionController?.updateCurrentSelection(currentSelection)
        }
    }

    private func handleCameraCommand(_ command: ImmersiveMapCameraCommand) {
        switch command {
        case .jump(let position):
            setCameraPosition(position)
        case .fly(let position, let options, let completion):
            fly(to: position,
                options: options,
                completion: completion)
        case .cancelFlight:
            cancelFlight()
        case .anchorAvatarMarker(let markerID, let verticalScreenOffsetFraction):
            anchorCamera(toAvatarMarkerWithID: markerID,
                         verticalScreenOffsetFraction: verticalScreenOffsetFraction)
        case .stopAnchoring:
            stopAnchoringCamera()
        }
    }

    private func handleSelectionCommand(_ command: ImmersiveMapSelectionCommand) -> Bool {
        switch command {
        case .select(let selection):
            return selectMapSelection(selection,
                                      source: .programmatic,
                                      screenPoint: nil)
        case .clear:
            return clearMapSelection(source: .programmatic,
                                     screenPoint: nil)
        }
    }

    func notifyCameraPositionChanged(_ position: ImmersiveMapCameraPosition? = nil) {
        guard let position = position ?? currentCameraPosition() else {
            return
        }

        cameraController?.notifyCameraPositionChanged(position)
    }

    func syncPitchControlValue(fallbackCameraPosition: ImmersiveMapCameraPosition? = nil) {
        let currentCameraPosition = cameraCoordinator?.currentCameraPosition()
            ?? fallbackCameraPosition
            ?? appliedCameraPosition
            ?? initialCameraPosition
        pitchControlZone.syncValue(cameraPosition: currentCameraPosition,
                                   maximumPitch: cameraCoordinator?.currentMaximumPitch() ?? settings.camera.maximumPitch)
    }

    func currentMapSelection() -> ImmersiveMapSelection? {
        currentSelection
    }

    @discardableResult
    func selectMapSelection(_ selection: ImmersiveMapSelection,
                            source: ImmersiveMapSelectionSource,
                            screenPoint: CGPoint?) -> Bool {
        guard isSelectionAvailable(selection) else {
            return false
        }

        if currentSelection == selection {
            return true
        }

        if let currentSelection {
            applySelectionVisualState(for: currentSelection, isSelected: false)
        }

        applySelectionVisualState(for: selection, isSelected: true)
        currentSelection = selection
        selectionController?.notifySelectionChanged(
            ImmersiveMapSelectionChangeEvent(selection: selection,
                                    source: source,
                                    screenPoint: screenPoint)
        )
        return true
    }

    @discardableResult
    func clearMapSelection(source: ImmersiveMapSelectionSource,
                           screenPoint: CGPoint?) -> Bool {
        guard let currentSelection else {
            return false
        }

        applySelectionVisualState(for: currentSelection, isSelected: false)
        self.currentSelection = nil
        selectionController?.notifySelectionCleared(
            ImmersiveMapSelectionClearEvent(previousSelection: currentSelection,
                                   source: source,
                                   screenPoint: screenPoint)
        )
        return true
    }

    func updateAvatarSelectionSnapshot(_ snapshot: AvatarSelectionSnapshot) {
        updateRenderLoopOnMain {
            guard snapshot.frameIndex >= self.avatarSelectionSnapshot.frameIndex else {
                return
            }
            self.avatarSelectionSnapshot = snapshot
        }
    }

    private func updateRenderLoopOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    func handleBackgroundTap(at point: CGPoint) {
        guard isControlZonePoint(point) == false else {
            return
        }

        cameraController?.notifyMapBackgroundTap()
    }

    func handleMapTap(at point: CGPoint) {
        guard isControlZonePoint(point) == false else {
            return
        }

        if let target = avatarHitTarget(at: point) {
            switch target {
            case .cluster:
                return
            case .marker:
                break
            }

            if selectionController != nil,
               let selection = selection(from: target) {
                _ = selectMapSelection(selection,
                                       source: .tap,
                                       screenPoint: point)
                return
            }
        }

        selectionController?.notifyMapBackgroundTap(at: point)
        _ = clearMapSelection(source: .tap,
                              screenPoint: point)
        cameraController?.notifyMapBackgroundTap()
    }

    private func isControlZonePoint(_ point: CGPoint) -> Bool {
        pitchControlZone.contains(point) || zoomControlZone.contains(point)
    }

    func handleAvatarControllerDidChange() {
        updateRenderLoopOnMain {
            self.syncSelectionWithAvailableMapObjects()
            self.requestFrame()
        }
    }

    private func syncSelectionWithAvailableMapObjects() {
        guard let currentSelection else {
            return
        }

        guard isSelectionAvailable(currentSelection) else {
            _ = clearMapSelection(source: .system,
                                  screenPoint: nil)
            return
        }
    }

    private func avatarHitTarget(at point: CGPoint) -> AvatarSelectionTarget? {
        guard avatarSelectionSnapshot.entries.isEmpty == false,
              avatarSelectionSnapshot.drawSize.height > 0 else {
            return nil
        }

        let scale = metalLayer.contentsScale
        let pixelPoint = CGPoint(x: point.x * scale,
                                 y: avatarSelectionSnapshot.drawSize.height - point.y * scale)
        return avatarSelectionSnapshot.hitTest(point: pixelPoint)
    }

    private func selection(from target: AvatarSelectionTarget?) -> ImmersiveMapSelection? {
        guard case .marker(let avatarID) = target else {
            return nil
        }

        let selection = ImmersiveMapSelection(kind: .avatar, objectID: avatarID)
        return isSelectionAvailable(selection) ? selection : nil
    }

    private func isSelectionAvailable(_ selection: ImmersiveMapSelection) -> Bool {
        switch selection.kind {
        case .avatar:
            return avatarsController?.marker(id: selection.objectID) != nil
        }
    }

    private func applySelectionVisualState(for selection: ImmersiveMapSelection,
                                           isSelected: Bool) {
        switch selection.kind {
        case .avatar:
            avatarsController?.update(id: selection.objectID,
                                      isSelected: isSelected)
        }
    }

    func syncAnchoredCameraToMarkerIfNeeded(forceReposition: Bool = false) {
        guard let anchoredAvatarMarkerID,
              let marker = avatarsController?.marker(id: anchoredAvatarMarkerID),
              let currentCameraPosition = currentCameraPosition() else {
            return
        }

        let shouldRecenter = forceReposition
            || lastAnchoredAvatarCoordinate != marker.coordinate
            || currentCameraPosition.latitudeDegrees != marker.coordinate.latitude
            || currentCameraPosition.longitudeDegrees != marker.coordinate.longitude
        guard shouldRecenter else {
            return
        }

        let nextCameraPosition = ImmersiveMapCameraPosition(latitudeDegrees: marker.coordinate.latitude,
                                                            longitudeDegrees: marker.coordinate.longitude,
                                                            zoom: currentCameraPosition.zoom,
                                                            bearing: currentCameraPosition.bearing,
                                                            pitch: currentCameraPosition.pitch)
        cameraCoordinator?.setCameraPosition(nextCameraPosition)
        applyViewportFocusPan(additionalLegacyVerticalOffsetFraction: anchoredAvatarVerticalScreenOffsetFraction)
        let adjustedCameraPosition = cameraCoordinator?.currentCameraPosition() ?? nextCameraPosition
        appliedCameraPosition = adjustedCameraPosition
        syncPitchControlValue(fallbackCameraPosition: adjustedCameraPosition)
        notifyCameraPositionChanged(adjustedCameraPosition)
        lastAnchoredAvatarCoordinate = marker.coordinate
    }

    private func applyViewportFocusPan(additionalLegacyVerticalOffsetFraction: CGFloat = 0) {
        guard let cameraCoordinator else {
            return
        }

        let screenOffset = viewportFocusScreenOffset(additionalLegacyVerticalOffsetFraction: additionalLegacyVerticalOffsetFraction)
        guard screenOffset != .zero else {
            return
        }

        cameraCoordinator.panCamera(deltaX: Double(screenOffset.x) * settings.camera.gesturePanTranslationScale,
                                    deltaY: Double(screenOffset.y) * settings.camera.gesturePanTranslationScale)
    }

    private func viewportFocusScreenOffset(additionalLegacyVerticalOffsetFraction: CGFloat = 0) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let legacyVerticalOffset = CGPoint(x: 0,
                                           y: -(bounds.height * max(0, additionalLegacyVerticalOffsetFraction)))

        return legacyVerticalOffset
    }

    var hasActiveUserInteraction: Bool {
        panInteractionActive
            || pinchInteractionActive
            || rotationInteractionActive
            || pitchInteractionActive
            || zoomControlInteractionActive
            || scrollZoomInteractionActive
    }

    private func makeGlobeCameraPanInertiaConfiguration() -> GlobeCameraPanInertia.Configuration {
        GlobeCameraPanInertia.Configuration(isEnabled: settings.camera.globePanInertiaEnabled,
                                            halfLife: settings.camera.globePanInertiaHalfLife,
                                            activationVelocity: settings.camera.globePanInertiaActivationVelocity,
                                            stopVelocity: settings.camera.globePanInertiaStopVelocity,
                                            maximumInitialVelocity: settings.camera.globePanInertiaMaxInitialVelocity)
    }

    private func startGlobeCameraPanInertiaIfNeeded(initialVelocity: CGPoint) {
        guard let cameraCoordinator,
              cameraCoordinator.isSphericalRenderBackendActive() else {
            cancelGlobeCameraPanInertia()
            return
        }

        let didStart = globeCameraPanInertia.start(initialVelocity: initialVelocity,
                                                   currentTime: CACurrentMediaTime())
        globeCameraPanInertiaIsActive = didStart
        refreshCameraAnimationRenderingState()
        if didStart {
            requestFrame()
        }
    }

    private func advanceGlobeCameraPanInertiaIfNeeded(currentTime: CFTimeInterval) {
        guard globeCameraPanInertiaIsActive else {
            refreshCameraAnimationRenderingState()
            return
        }

        guard hasActiveUserInteraction == false,
              let cameraCoordinator,
              cameraCoordinator.isSphericalRenderBackendActive() else {
            cancelGlobeCameraPanInertia()
            return
        }

        let step = globeCameraPanInertia.advance(currentTime: currentTime)
        globeCameraPanInertiaIsActive = step.isActive
        if step.translation != .zero {
            cameraCoordinator.panCamera(deltaX: Double(step.translation.x) * settings.camera.gesturePanTranslationScale,
                                        deltaY: Double(step.translation.y) * settings.camera.gesturePanTranslationScale)
            notifyCameraPositionChanged()
            requestFrame()
        }

        if step.isActive == false {
            refreshCameraAnimationRenderingState()
        }
    }

    func advanceCameraFlightIfNeeded(currentTime: CFTimeInterval) {
        guard cameraFlightAnimator.isActive else {
            refreshCameraAnimationRenderingState()
            return
        }

        guard hasActiveUserInteraction == false,
              let cameraCoordinator else {
            cancelCameraFlight()
            return
        }

        guard let step = cameraFlightAnimator.advance(currentTime: currentTime) else {
            refreshCameraAnimationRenderingState()
            return
        }

        cameraCoordinator.setCameraState(step.cameraState)
        syncPitchControlValue()
        notifyCameraPositionChanged()
        requestFrame()

        guard step.didFinish else {
            refreshCameraAnimationRenderingState()
            return
        }

        if let cameraFlightTargetPosition {
            cameraCoordinator.setCameraPosition(cameraFlightTargetPosition)
            appliedCameraPosition = cameraFlightTargetPosition
            syncPitchControlValue(fallbackCameraPosition: cameraFlightTargetPosition)
            notifyCameraPositionChanged()
        }
        finishCameraFlight(success: true)
    }

    private func cancelGlobeCameraPanInertia() {
        globeCameraPanInertia.cancel()
        globeCameraPanInertiaIsActive = false
        refreshCameraAnimationRenderingState()
    }

    private func createRenderer(settings: ImmersiveMapSettings,
                                cameraPosition: ImmersiveMapCameraPosition?) {
        let cameraCoordinator = ImmersiveMapCameraCoordinator(settings: settings)
        self.cameraCoordinator = cameraCoordinator
        let events = RenderFrameEvents(invalidate: { [weak self] reason in
                                         self?.mapRenderLoop.invalidate(reason: reason)
                                     },
                                     activityChanged: { [weak self] state in
                                         self?.mapRenderLoop.applyActivityState(state)
                                     },
                                     avatarSelectionSnapshotUpdated: { [weak self] snapshot in
                                         self?.updateAvatarSelectionSnapshot(snapshot)
                                     })
        let renderer = Renderer(layer: metalLayer,
                                avatarsControllerProvider: { [weak self] in
                                    self?.avatarsController
                                },
                                config: settings,
                                cameraCoordinator: cameraCoordinator,
                                events: events)
        mapRenderLoop.replaceRenderer(renderer)
        avatarsController?.markSnapshotDirty()
        if let cameraPosition {
            cameraCoordinator.setCameraPosition(cameraPosition)
            appliedCameraPosition = cameraPosition
        }
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        requestFrame()
    }

    private func recreateRenderer(with settings: ImmersiveMapSettings) {
        cancelCameraAnimations(notifyFlightCompletion: false)
        let cameraPosition = cameraCoordinator?.currentCameraPosition() ?? appliedCameraPosition ?? initialCameraPosition
        mapRenderLoop.replaceRenderer(nil)
        cameraCoordinator = nil
        createRenderer(settings: settings,
                       cameraPosition: cameraPosition)
    }

    deinit {
        globeCameraPanInertia.cancel()
        globeCameraPanInertiaIsActive = false
        cameraFlightAnimator.cancel()
        cameraFlightCompletion = nil
        cameraFlightTargetPosition = nil
        avatarsController?.setChangeHandler(nil)
        cameraController?.setCommandHandler(nil)
        cameraController?.updateCurrentCameraPosition(nil)
        let detachedSelectionController = selectionController
        Task { @MainActor in
            detachedSelectionController?.setCommandHandler(nil)
            detachedSelectionController?.updateCurrentSelection(nil)
        }
        mapRenderLoop.invalidateDisplayLink()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }
}
