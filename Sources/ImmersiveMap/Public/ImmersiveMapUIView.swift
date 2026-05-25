//
//  ImmersiveMapView.swift
//  ImmersiveMapFramework
//  Created by Artem on 8/31/25.
//

import UIKit
import Metal
import QuartzCore

enum PitchControlMath {
    static func clampedControlValue(_ value: Float, maximumPitch: Float) -> Float {
        min(max(0, value), maximumPitch)
    }

    static func actualPitch(forControlValue value: Float, maximumPitch: Float) -> Float {
        maximumPitch - clampedControlValue(value, maximumPitch: maximumPitch)
    }

    static func controlValue(forActualPitch pitch: Float, maximumPitch: Float) -> Float {
        clampedControlValue(maximumPitch - min(max(0, pitch), maximumPitch), maximumPitch: maximumPitch)
    }

    static func controlValueDelta(forVerticalTranslation translationY: CGFloat,
                                  interactionHeight: CGFloat,
                                  maximumPitch: Float) -> Float {
        guard interactionHeight > 0, maximumPitch > 0 else {
            return 0
        }

        return -Float(translationY / interactionHeight) * maximumPitch
    }
}

#if DEBUG
extension ImmersiveMapUIView {
    func flyForTesting(to cameraPosition: ImmersiveMapCameraPosition,
                       options: CameraFlightOptions = .default,
                       completion: ((Bool) -> Void)? = nil,
                       currentTime: CFTimeInterval) {
        startCameraFlight(to: cameraPosition,
                          options: options,
                          completion: completion,
                          currentTime: currentTime)
    }

    func advanceCameraFlightForTesting(currentTime: CFTimeInterval) {
        advanceCameraFlightIfNeeded(currentTime: currentTime)
    }

    func setPanInteractionActiveForTesting(_ isActive: Bool) {
        let wasInteracting = hasActiveUserInteraction
        panInteractionActive = isActive
        if isActive && !wasInteracting {
            cameraController?.notifyUserInteractionBegan()
        }
        if isActive {
            cancelCameraAnimations()
        }
        updateCombinedInteractionRenderingState()
    }

    var hasActiveCameraFlightForTesting: Bool {
        cameraFlightController.isActive
    }

    var isCameraAnimationRenderingActiveForTesting: Bool {
        renderLoopScheduler.cameraAnimationRenderingActive
    }

    func simulateBackgroundTapForTesting(at point: CGPoint) {
        handleBackgroundTap(at: point)
    }

    func simulateMapTapForTesting(at point: CGPoint) {
        handleMapTap(at: point)
    }

    func setAvatarSelectionSnapshotForTesting(_ snapshot: AvatarSelectionSnapshot) {
        avatarSelectionSnapshot = snapshot
    }

    func syncAnchoredCameraForTesting() {
        syncAnchoredCameraToMarkerIfNeeded()
    }
}
#endif

enum ZoomControlMath {
    static func zoomDelta(forVerticalTranslation translationY: CGFloat,
                          velocityY: CGFloat,
                          interactionHeight: CGFloat,
                          zoomFactor: Double,
                          velocityFactor: Double,
                          velocityLimit: Double) -> Double {
        guard interactionHeight > 0,
              zoomFactor.isFinite,
              velocityFactor.isFinite,
              velocityLimit.isFinite else {
            return 0
        }

        let normalizedTranslation = -Double(translationY / interactionHeight)
        let baseDelta = normalizedTranslation * zoomFactor
        guard baseDelta.isFinite, baseDelta != 0 else {
            return 0
        }

        let normalizedVelocity = -Double(velocityY / interactionHeight)
        let alignedVelocityMagnitude: Double
        if normalizedVelocity.isFinite, baseDelta * normalizedVelocity > 0 {
            alignedVelocityMagnitude = min(abs(normalizedVelocity), max(0, velocityLimit))
        } else {
            alignedVelocityMagnitude = 0
        }

        let boost = 1.0 + alignedVelocityMagnitude * max(0, velocityFactor)
        return baseDelta * boost
    }
}

private final class ControlZoneView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class ImmersiveMapUIView: UIView, UIGestureRecognizerDelegate {
    private static let pitchControlZoneSize = CGSize(width: 88, height: 188)
    private static let pitchControlBottomInset: CGFloat = 0
    private static let pitchControlLeadingInset: CGFloat = 0
    private static let zoomControlZoneSize = CGSize(width: 132, height: 240)
    private static let zoomControlBottomInset: CGFloat = 0
    private static let zoomControlTrailingInset: CGFloat = 0

    public override class var layerClass: AnyClass { return CAMetalLayer.self }
    
    private var settings: MapSettings
    private let initialCameraPosition: ImmersiveMapCameraPosition?
    private let initialVisibilityPolicy: VisibilityPolicy
    public let avatarsController: AvatarsController
    
    override init(frame: CGRect) {
        self.settings = .default
        self.initialCameraPosition = nil
        self.initialVisibilityPolicy = .followPresentation
        self.avatarsController = AvatarsController()
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        self.settings = .default
        self.initialCameraPosition = nil
        self.initialVisibilityPolicy = .followPresentation
        self.avatarsController = AvatarsController()
        super.init(coder: coder)
        setup()
    }
    
    init(frame: CGRect,
         settings: MapSettings,
         avatarsController: AvatarsController = AvatarsController(),
         cameraPosition: ImmersiveMapCameraPosition? = nil,
         visibilityPolicy: VisibilityPolicy = .followPresentation) {
        self.settings = settings
        self.initialCameraPosition = cameraPosition
        self.initialVisibilityPolicy = visibilityPolicy
        self.avatarsController = avatarsController
        super.init(frame: frame)
        setup()
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
        
        pitchControlZone.frame = CGRect(
            x: Self.pitchControlLeadingInset,
            y: bounds.height - Self.pitchControlBottomInset - Self.pitchControlZoneSize.height,
            width: Self.pitchControlZoneSize.width,
            height: Self.pitchControlZoneSize.height
        )
        zoomControlZone.frame = CGRect(
            x: bounds.width - Self.zoomControlTrailingInset - Self.zoomControlZoneSize.width,
            y: bounds.height - Self.zoomControlBottomInset - Self.zoomControlZoneSize.height,
            width: Self.zoomControlZoneSize.width,
            height: Self.zoomControlZoneSize.height
        )
    }
    
    private var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    private var mapPanGesture: UIPanGestureRecognizer!
    private var mapTapGesture: UITapGestureRecognizer!
    private var pitchControlPanGesture: UIPanGestureRecognizer!
    private var zoomControlPanGesture: UIPanGestureRecognizer!
    private var pitchControlZone: ControlZoneView!
    private var zoomControlZone: ControlZoneView!
    private var pitchControlValue: Float = 0
    private var renderer: Renderer?
    private var appliedCameraPosition: ImmersiveMapCameraPosition?
    private var displayLink: CADisplayLink?
    private var memoryWarningObserver: NSObjectProtocol?
    private lazy var renderLoopScheduler = RenderLoopScheduler(configuration: settings.renderLoop)
    private lazy var globePanInertiaController = GlobePanInertiaController(configuration: makeGlobePanInertiaConfiguration())
    private let cameraFlightController = CameraFlightController()
    private var cameraFlightTargetPosition: ImmersiveMapCameraPosition?
    private var cameraFlightCompletion: ((Bool) -> Void)?
    private var panInteractionActive: Bool = false
    private var pinchInteractionActive: Bool = false
    private var rotationInteractionActive: Bool = false
    private var pitchInteractionActive: Bool = false
    private var zoomControlInteractionActive: Bool = false
    private weak var cameraController: MapCameraController?
    private weak var selectionController: MapSelectionController?
    private var currentSelection: MapSelection?
    private var avatarSelectionSnapshot: AvatarSelectionSnapshot = .empty
    private var anchoredAvatarMarkerID: UInt64?
    private var anchoredAvatarVerticalScreenOffsetFraction: CGFloat = 0
    private var lastAnchoredAvatarCoordinate: GeoCoordinate?
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: self, selector: #selector(renderLoop))
        displayLink?.add(to: .main, forMode: .common)
        applyDisplayLinkState()
    }
    
    private func setup() {
        metalLayer.contentsScale = UIScreen.main.scale
        avatarsController.setChangeHandler { [weak self] in
            self?.handleAvatarControllerDidChange()
        }
        createRenderer(settings: settings,
                       visibilityPolicy: initialVisibilityPolicy,
                       cameraPosition: initialCameraPosition)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderer?.handleMemoryWarning()
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
        
        pitchControlZone = ControlZoneView()
        pitchControlZone.accessibilityIdentifier = "ImmersiveMapUIView.pitchControlZone"
        addSubview(pitchControlZone)

        pitchControlPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePitchZonePan(_:)))
        pitchControlPanGesture.maximumNumberOfTouches = 1
        pitchControlZone.addGestureRecognizer(pitchControlPanGesture)
        mapPanGesture.require(toFail: pitchControlPanGesture)

        zoomControlZone = ControlZoneView()
        zoomControlZone.accessibilityIdentifier = "ImmersiveMapUIView.zoomControlZone"
        addSubview(zoomControlZone)

        zoomControlPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleZoomZonePan(_:)))
        zoomControlPanGesture.maximumNumberOfTouches = 1
        zoomControlZone.addGestureRecognizer(zoomControlPanGesture)
        mapPanGesture.require(toFail: zoomControlPanGesture)
        syncPitchControlValue()
        
        startDisplayLink()
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
        renderer?.switchRenderMode()
        syncPitchControlValue()
        requestFrame()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        handleMapTap(at: gesture.location(in: self))
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let renderer = renderer else { return }
        updateInteractionState(for: gesture.state, gestureKind: .rotation)
        let rotation = gesture.rotation
        renderer.rotateCameraYaw(delta: Float(rotation) * settings.camera.rotationGestureSensitivity)
        notifyCameraPositionChanged()
        // Reset rotation to accumulate changes
        gesture.rotation = 0
        requestFrame()
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let renderer = renderer else { return }
        updateInteractionState(for: gesture.state, gestureKind: .pan)
        
        let translation = gesture.translation(in: self)
        renderer.panCamera(deltaX: Double(translation.x) * settings.camera.gesturePanTranslationScale,
                           deltaY: Double(translation.y) * settings.camera.gesturePanTranslationScale)
        notifyCameraPositionChanged()

        // Reset translation to accumulate changes
        gesture.setTranslation(.zero, in: self)
        
        // Redraw view after panning
        requestFrame()

        switch gesture.state {
        case .ended:
            startGlobePanInertiaIfNeeded(initialVelocity: gesture.velocity(in: self))
        case .cancelled, .failed:
            cancelGlobePanInertia()
        case .began, .changed, .possible:
            break
        @unknown default:
            cancelGlobePanInertia()
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let renderer = renderer else { return }
        updateInteractionState(for: gesture.state, gestureKind: .pinch)
        
        let scale = gesture.scale
        renderer.zoomCamera(scale: scale, velocity: gesture.velocity)
        notifyCameraPositionChanged()
        gesture.scale = 1.0
        syncPitchControlValue()
        requestFrame()
    }
    
    @objc private func handlePitchZonePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            gesture.setTranslation(.zero, in: pitchControlZone)
            setPitchInteractionActive(true)
        case .changed:
            let translation = gesture.translation(in: pitchControlZone)
            let delta = PitchControlMath.controlValueDelta(
                forVerticalTranslation: translation.y,
                interactionHeight: pitchControlZone.bounds.height,
                maximumPitch: currentMaximumPitch()
            )
            setPitchControlValue(pitchControlValue + delta, updateCamera: true)
            gesture.setTranslation(.zero, in: pitchControlZone)
        case .ended, .cancelled, .failed:
            setPitchInteractionActive(false)
        case .possible:
            break
        @unknown default:
            setPitchInteractionActive(false)
        }
    }

    @objc private func handleZoomZonePan(_ gesture: UIPanGestureRecognizer) {
        guard let renderer else { return }

        switch gesture.state {
        case .began:
            gesture.setTranslation(.zero, in: zoomControlZone)
            setZoomControlInteractionActive(true)
        case .changed:
            let translation = gesture.translation(in: zoomControlZone)
            let velocity = gesture.velocity(in: zoomControlZone)
            let delta = ZoomControlMath.zoomDelta(forVerticalTranslation: translation.y,
                                                  velocityY: velocity.y,
                                                  interactionHeight: zoomControlZone.bounds.height,
                                                  zoomFactor: settings.camera.dragZoomFactor,
                                                  velocityFactor: settings.camera.dragZoomVelocityFactor,
                                                  velocityLimit: settings.camera.dragZoomVelocityLimit)
            renderer.zoomCamera(delta: delta)
            notifyCameraPositionChanged()
            gesture.setTranslation(.zero, in: zoomControlZone)
            syncPitchControlValue()
            requestFrame()
        case .ended, .cancelled, .failed:
            setZoomControlInteractionActive(false)
        case .possible:
            break
        @unknown default:
            setZoomControlInteractionActive(false)
        }
    }

    private func setPitchInteractionActive(_ isActive: Bool) {
        if isActive {
            cancelCameraAnimations()
        }
        pitchInteractionActive = isActive
        updateCombinedInteractionRenderingState()
        if isActive {
            requestFrame()
        }
    }

    private func setZoomControlInteractionActive(_ isActive: Bool) {
        if isActive {
            cancelCameraAnimations()
        }
        zoomControlInteractionActive = isActive
        updateCombinedInteractionRenderingState()
        if isActive {
            requestFrame()
        }
    }

    private func setPitchControlValue(_ value: Float, updateCamera: Bool) {
        let maximumPitch = currentMaximumPitch()
        let clampedValue = PitchControlMath.clampedControlValue(value, maximumPitch: maximumPitch)
        pitchControlValue = clampedValue

        guard updateCamera, let renderer else {
            return
        }

        renderer.setCameraPitch(PitchControlMath.actualPitch(forControlValue: clampedValue,
                                                             maximumPitch: maximumPitch))
        requestFrame()
    }
    
    @objc private func renderLoop() {
        guard renderLoopScheduler.shouldRenderFrame else {
            applyDisplayLinkState()
            return
        }

        let currentTime = CACurrentMediaTime()
        advanceGlobePanInertiaIfNeeded(currentTime: currentTime)
        advanceCameraFlightIfNeeded(currentTime: currentTime)
        syncAnchoredCameraToMarkerIfNeeded()
        guard renderLoopScheduler.shouldRenderFrame else {
            applyDisplayLinkState()
            return
        }

        let didSchedule = render()
        if didSchedule {
            renderLoopScheduler.markFrameScheduled()
        }
        applyDisplayLinkState()
    }
    
    @discardableResult
    private func render() -> Bool {
        if bounds.width > 0 && bounds.height > 0 {
            return renderer?.render(to: metalLayer) ?? false
        }
        return false
    }

    public func setVisibilityPolicy(_ policy: VisibilityPolicy) {
        renderer?.setVisibilityPolicy(policy)
        requestFrame()
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
        cancelCameraAnimations()
        guard appliedCameraPosition != cameraPosition else {
            return
        }

        appliedCameraPosition = cameraPosition
        guard let cameraPosition else {
            return
        }

        renderer?.setCameraPosition(cameraPosition)
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
        requestFrame()
    }

    public func currentCameraPosition() -> ImmersiveMapCameraPosition? {
        renderer?.currentCameraPosition() ?? appliedCameraPosition ?? initialCameraPosition
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

    func applySettings(_ settings: MapSettings) {
        guard self.settings != settings else {
            return
        }

        let plan = MapSettings.makeApplicationPlan(from: self.settings, to: settings)
        self.settings = settings
        globePanInertiaController.updateConfiguration(makeGlobePanInertiaConfiguration())
        if settings.camera.globePanInertiaEnabled == false {
            cancelGlobePanInertia()
        }
        renderLoopScheduler.updateConfiguration(settings.renderLoop)
        if plan.requiresRendererRecreation {
            recreateRenderer(with: settings)
        } else {
            renderer?.applySettings(settings)
        }

        syncPitchControlValue()
        applyDisplayLinkState()
        requestFrame()
    }

    func requestFrame() {
        updateRenderLoopOnMain {
            self.renderLoopScheduler.requestFrame()
            self.applyDisplayLinkState()
        }
    }

    func setLabelFadeRenderingActive(_ isActive: Bool) {
        updateRenderLoopOnMain {
            self.renderLoopScheduler.setLabelFadeRenderingActive(isActive)
            self.applyDisplayLinkState()
        }
    }

    func setBaseLabelFadeRenderingActive(_ isActive: Bool) {
        setLabelFadeRenderingActive(isActive)
    }

    func setLabelVisibilityCycleRenderingActive(_ isActive: Bool) {
        updateRenderLoopOnMain {
            self.renderLoopScheduler.setLabelVisibilityCycleRenderingActive(isActive)
            self.applyDisplayLinkState()
        }
    }

    func setCameraAnimationRenderingActive(_ isActive: Bool) {
        updateRenderLoopOnMain {
            self.renderLoopScheduler.setCameraAnimationRenderingActive(isActive)
            self.applyDisplayLinkState()
        }
    }

    func setAvatarAnimationRenderingActive(_ isActive: Bool) {
        updateRenderLoopOnMain {
            self.renderLoopScheduler.setAvatarAnimationRenderingActive(isActive)
            self.applyDisplayLinkState()
        }
    }

    private func refreshCameraAnimationRenderingState() {
        setCameraAnimationRenderingActive(globePanInertiaController.isActive || cameraFlightController.isActive)
    }

    private func startCameraFlight(to cameraPosition: ImmersiveMapCameraPosition,
                                   options: CameraFlightOptions,
                                   completion: ((Bool) -> Void)?,
                                   currentTime: CFTimeInterval) {
        guard let renderer else {
            completion?(false)
            return
        }

        cancelCameraAnimations()
        let startState = renderer.currentCameraState()
        let targetState = MapCameraState(cameraPosition: cameraPosition,
                                         cameraSettings: settings.camera)
        if CameraFlightMath.hasMeaningfulDelta(from: startState, to: targetState) == false || options.duration <= 0 {
            appliedCameraPosition = cameraPosition
            renderer.setCameraPosition(cameraPosition)
            syncPitchControlValue(fallbackCameraPosition: cameraPosition)
            notifyCameraPositionChanged()
            requestFrame()
            completion?(true)
            return
        }

        let resolvedRouteStyle = resolveCameraFlightRouteStyle(options.routeStyle,
                                                               startState: startState,
                                                               targetState: targetState)
        let didStart = cameraFlightController.start(from: startState,
                                                    to: targetState,
                                                    duration: options.duration,
                                                    routeStyle: resolvedRouteStyle,
                                                    altitudeStyle: options.altitudeStyle,
                                                    currentTime: currentTime)
        guard didStart else {
            appliedCameraPosition = cameraPosition
            renderer.setCameraPosition(cameraPosition)
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
                                               startState: MapCameraState,
                                               targetState: MapCameraState) -> CameraFlightController.ResolvedRouteStyle {
        switch routeStyle {
        case .mercatorShortestPath:
            return .mercatorShortestPath
        case .greatCircle:
            return .greatCircle
        case .automatic:
            guard let renderer else {
                return .mercatorShortestPath
            }

            let automaticTransitionStartZoom = settings.presentation.automaticTransitionStartZoom
            let useGreatCircle = renderer.isSphericalRenderBackendActive()
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
        guard cameraFlightController.isActive || cameraFlightCompletion != nil else {
            refreshCameraAnimationRenderingState()
            return
        }

        cameraFlightController.cancel()
        if notifyCompletion {
            finishCameraFlight(success: false)
        } else {
            cameraFlightCompletion = nil
            cameraFlightTargetPosition = nil
            refreshCameraAnimationRenderingState()
        }
    }

    private func cancelCameraAnimations(notifyFlightCompletion: Bool = true) {
        cancelGlobePanInertia()
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

    private func updateCombinedInteractionRenderingState() {
        renderLoopScheduler.setInteractionRenderingActive(hasActiveUserInteraction)
        applyDisplayLinkState()
    }

    func attach(cameraController: MapCameraController?) {
        self.cameraController = cameraController
        notifyCameraPositionChanged()
    }

    func attach(selectionController: MapSelectionController?) {
        self.selectionController = selectionController
    }

    private func notifyCameraPositionChanged(_ position: ImmersiveMapCameraPosition? = nil) {
        guard let position = position ?? currentCameraPosition() else {
            return
        }

        cameraController?.notifyCameraPositionChanged(position)
    }

    func currentMapSelection() -> MapSelection? {
        currentSelection
    }

    @discardableResult
    func selectMapSelection(_ selection: MapSelection,
                            source: MapSelectionSource,
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
            MapSelectionChangeEvent(selection: selection,
                                    source: source,
                                    screenPoint: screenPoint)
        )
        return true
    }

    @discardableResult
    func clearMapSelection(source: MapSelectionSource,
                           screenPoint: CGPoint?) -> Bool {
        guard let currentSelection else {
            return false
        }

        applySelectionVisualState(for: currentSelection, isSelected: false)
        self.currentSelection = nil
        selectionController?.notifySelectionCleared(
            MapSelectionClearEvent(previousSelection: currentSelection,
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

    private func applyDisplayLinkState() {
        displayLink?.preferredFramesPerSecond = renderLoopScheduler.preferredFramesPerSecond
        displayLink?.isPaused = renderLoopScheduler.shouldPauseDisplayLink
    }

    private func updateRenderLoopOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func syncPitchControlValue(fallbackCameraPosition: ImmersiveMapCameraPosition? = nil) {
        let currentCameraPosition = renderer?.currentCameraPosition()
            ?? fallbackCameraPosition
            ?? appliedCameraPosition
            ?? initialCameraPosition
        let maximumPitch = currentMaximumPitch()
        if let currentCameraPosition {
            setPitchControlValue(PitchControlMath.controlValue(forActualPitch: currentCameraPosition.pitch,
                                                               maximumPitch: maximumPitch),
                                 updateCamera: false)
        } else {
            setPitchControlValue(maximumPitch, updateCamera: false)
        }
    }

    private func currentMaximumPitch() -> Float {
        renderer?.currentMaximumPitch() ?? settings.camera.maximumPitch
    }

    private func handleBackgroundTap(at point: CGPoint) {
        guard pitchControlZone.frame.contains(point) == false,
              zoomControlZone.frame.contains(point) == false else {
            return
        }

        cameraController?.notifyMapBackgroundTap()
    }

    private func handleMapTap(at point: CGPoint) {
        guard pitchControlZone.frame.contains(point) == false,
              zoomControlZone.frame.contains(point) == false else {
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

    private func handleAvatarControllerDidChange() {
        updateRenderLoopOnMain {
            self.syncSelectionWithAvailableMapObjects()
            self.renderLoopScheduler.requestFrame()
            self.applyDisplayLinkState()
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

    private func selection(from target: AvatarSelectionTarget?) -> MapSelection? {
        guard case .marker(let avatarID) = target else {
            return nil
        }

        let selection = MapSelection(kind: .avatar, objectID: avatarID)
        return isSelectionAvailable(selection) ? selection : nil
    }

    private func isSelectionAvailable(_ selection: MapSelection) -> Bool {
        switch selection.kind {
        case .avatar:
            return avatarsController.marker(id: selection.objectID) != nil
        }
    }

    private func applySelectionVisualState(for selection: MapSelection,
                                           isSelected: Bool) {
        switch selection.kind {
        case .avatar:
            avatarsController.update(id: selection.objectID,
                                     isSelected: isSelected)
        }
    }

    private func syncAnchoredCameraToMarkerIfNeeded(forceReposition: Bool = false) {
        guard let anchoredAvatarMarkerID,
              let marker = avatarsController.marker(id: anchoredAvatarMarkerID),
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
        renderer?.setCameraPosition(nextCameraPosition)
        applyViewportFocusPan(additionalLegacyVerticalOffsetFraction: anchoredAvatarVerticalScreenOffsetFraction)
        let adjustedCameraPosition = renderer?.currentCameraPosition() ?? nextCameraPosition
        appliedCameraPosition = adjustedCameraPosition
        syncPitchControlValue(fallbackCameraPosition: adjustedCameraPosition)
        notifyCameraPositionChanged(adjustedCameraPosition)
        lastAnchoredAvatarCoordinate = marker.coordinate
    }

    private func applyViewportFocusPan(additionalLegacyVerticalOffsetFraction: CGFloat = 0) {
        guard let renderer else {
            return
        }

        let screenOffset = viewportFocusScreenOffset(additionalLegacyVerticalOffsetFraction: additionalLegacyVerticalOffsetFraction)
        guard screenOffset != .zero else {
            return
        }

        renderer.panCamera(deltaX: Double(screenOffset.x) * settings.camera.gesturePanTranslationScale,
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

    private var hasActiveUserInteraction: Bool {
        panInteractionActive
            || pinchInteractionActive
            || rotationInteractionActive
            || pitchInteractionActive
            || zoomControlInteractionActive
    }

    private func makeGlobePanInertiaConfiguration() -> GlobePanInertiaController.Configuration {
        GlobePanInertiaController.Configuration(isEnabled: settings.camera.globePanInertiaEnabled,
                                                halfLife: settings.camera.globePanInertiaHalfLife,
                                                activationVelocity: settings.camera.globePanInertiaActivationVelocity,
                                                stopVelocity: settings.camera.globePanInertiaStopVelocity,
                                                maximumInitialVelocity: settings.camera.globePanInertiaMaxInitialVelocity)
    }

    private func startGlobePanInertiaIfNeeded(initialVelocity: CGPoint) {
        guard let renderer,
              renderer.isSphericalRenderBackendActive() else {
            cancelGlobePanInertia()
            return
        }

        let didStart = globePanInertiaController.start(initialVelocity: initialVelocity,
                                                       currentTime: CACurrentMediaTime())
        if didStart {
            refreshCameraAnimationRenderingState()
        } else {
            cancelGlobePanInertia()
        }
        if didStart {
            requestFrame()
        }
    }

    private func advanceGlobePanInertiaIfNeeded(currentTime: CFTimeInterval) {
        guard globePanInertiaController.isActive else {
            refreshCameraAnimationRenderingState()
            return
        }

        guard hasActiveUserInteraction == false,
              let renderer,
              renderer.isSphericalRenderBackendActive() else {
            cancelGlobePanInertia()
            return
        }

        let translation = globePanInertiaController.advance(currentTime: currentTime)
        if translation != .zero {
            renderer.panCamera(deltaX: Double(translation.x) * settings.camera.gesturePanTranslationScale,
                               deltaY: Double(translation.y) * settings.camera.gesturePanTranslationScale)
            notifyCameraPositionChanged()
            requestFrame()
        }

        if globePanInertiaController.isActive == false {
            refreshCameraAnimationRenderingState()
        }
    }

    private func advanceCameraFlightIfNeeded(currentTime: CFTimeInterval) {
        guard cameraFlightController.isActive else {
            refreshCameraAnimationRenderingState()
            return
        }

        guard hasActiveUserInteraction == false,
              let renderer else {
            cancelCameraFlight()
            return
        }

        guard let step = cameraFlightController.advance(currentTime: currentTime) else {
            refreshCameraAnimationRenderingState()
            return
        }

        renderer.setCameraState(step.cameraState)
        syncPitchControlValue()
        notifyCameraPositionChanged()
        requestFrame()

        guard step.didFinish else {
            refreshCameraAnimationRenderingState()
            return
        }

        if let cameraFlightTargetPosition {
            renderer.setCameraPosition(cameraFlightTargetPosition)
            appliedCameraPosition = cameraFlightTargetPosition
            syncPitchControlValue(fallbackCameraPosition: cameraFlightTargetPosition)
            notifyCameraPositionChanged()
        }
        finishCameraFlight(success: true)
    }

    private func cancelGlobePanInertia() {
        if globePanInertiaController.isActive {
            globePanInertiaController.cancel()
        }
        refreshCameraAnimationRenderingState()
    }

    private func createRenderer(settings: MapSettings,
                                visibilityPolicy: VisibilityPolicy,
                                cameraPosition: ImmersiveMapCameraPosition?) {
        let renderer = Renderer(layer: metalLayer, uiView: self, config: settings)
        self.renderer = renderer
        renderer.setVisibilityPolicy(visibilityPolicy)
        if let cameraPosition {
            renderer.setCameraPosition(cameraPosition)
            appliedCameraPosition = cameraPosition
        }
        syncPitchControlValue(fallbackCameraPosition: cameraPosition)
        notifyCameraPositionChanged()
    }

    private func recreateRenderer(with settings: MapSettings) {
        cancelCameraAnimations(notifyFlightCompletion: false)
        let cameraPosition = renderer?.currentCameraPosition() ?? appliedCameraPosition ?? initialCameraPosition
        let visibilityPolicy = renderer?.currentVisibilityPolicy() ?? initialVisibilityPolicy
        renderer = nil
        createRenderer(settings: settings,
                       visibilityPolicy: visibilityPolicy,
                       cameraPosition: cameraPosition)
    }

    deinit {
        globePanInertiaController.cancel()
        cameraFlightController.cancel()
        cameraFlightCompletion = nil
        cameraFlightTargetPosition = nil
        avatarsController.setChangeHandler(nil)
        displayLink?.invalidate()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }
}
