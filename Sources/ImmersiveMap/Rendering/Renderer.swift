//
//  Renderer.swift
//  ImmersiveMapFramework
//  Created by Artem on 8/31/25.
//

import Foundation
import simd
import Metal
import MetalKit
import QuartzCore

class Renderer {
    static let inFlightFramesCount: Int = 3

    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    private let metalLibrary: MTLLibrary
    private(set) var settings: MapSettings
    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let extrudedTilePipeline: ExtrudedTilePipeline
    let globePipeline: GlobePipeline
    let globeCapRenderer: GlobeCapRenderer
    let starfield: Starfield
    let camera: Camera
    let cameraControl: CameraControl
    let tileCulling: TileCulling
    var transition: Float = 0

    private var tileRenderStore: TileRenderStore
    private let tilesTexture: TilesTexture
    let textRenderer: TextRenderer
    let poiSpriteAtlas: PoiSpriteAtlas
    private let uiView: ImmersiveMapUIView
    let debugOverlayRenderer: DebugOverlayRenderer

    private let baseGridBuffers: GridBuffers
    private var lastDrawableSize: CGSize = .zero
    private let maxLatitude = 2.0 * atan(exp(Double.pi)) - Double.pi / 2.0

    private let inFlightFramePool = InFlightFramePool(slotsCount: Renderer.inFlightFramesCount)

    private let startDate = Date()
    private var frameIndex: UInt64 = 0
    private var previousFrameTime: TimeInterval = 0
    var currentDiagnostics: FrameDiagnostics?

    private let renderModeController: RenderModeController
    private let screenMatrix: ScreenMatrix = ScreenMatrix()

    let baseLabelCache: BaseLabelCache
    let roadLabelCache: RoadLabelCache
    private let flatTileOriginCalculator: FlatTileOriginCalculator

    let extrudedDepthState: MTLDepthStencilState
    let extrudedColorPassDepthState: MTLDepthStencilState
    let globeCapDepthState: MTLDepthStencilState
    let depthDisabledState: MTLDepthStencilState
    private var depthTexture: MTLTexture?
    private var buildingWinnerIDTexture: MTLTexture?
    private var buildingWinnerDepthTexture: MTLTexture?

    let avatarsController: AvatarsController
    let avatarsRenderer: AvatarsRenderer

    private let resourceRegistry = RenderResourceRegistry()
    private var tileGlobeTextureSubsystemRef: TileGlobeTextureSubsystem?
    private var baseLabelDrawSubsystemRef: BaseLabelDrawSubsystem?
    private var roadLabelDrawSubsystemRef: RoadLabelDrawSubsystem?
    private var avatarSubsystemRef: AvatarRenderSubsystem?
    private lazy var subsystemRegistry: RenderSubsystemRegistry = buildSubsystemRegistry()

    init(layer: CAMetalLayer, uiView: ImmersiveMapUIView, config: MapSettings = .default) {
        self.uiView = uiView
        self.settings = config
        let metal = RendererSetup.buildMetal(layer: layer)
        self.metalDevice = metal.device
        self.commandQueue = metal.commandQueue
        self.metalLibrary = metal.library

        self.extrudedDepthState = metal.device.makeDepthStencilState(descriptor: Self.makeSceneDepthDescriptor())!
        self.extrudedColorPassDepthState = metal.device.makeDepthStencilState(descriptor: Self.makeTransparentExtrudedDepthDescriptor())!
        self.globeCapDepthState = metal.device.makeDepthStencilState(descriptor: Self.makeGlobeCapDepthDescriptor())!
        self.depthDisabledState = metal.device.makeDepthStencilState(descriptor: Self.makeDepthDisabledDescriptor())!

        let mapStyle = DefaultMapStyle(settings: config.style)
        let mapBaseColors = mapStyle.getMapBaseColors()

        let pipelineFactory = RenderPipelineFactory(metalDevice: metal.device,
                                                    layer: layer,
                                                    library: metalLibrary,
                                                    config: config)
        let pipelines = pipelineFactory.makeRenderPipelines()
        polygonPipeline = pipelines.polygonPipeline
        tilePipeline = pipelines.tilePipeline
        extrudedTilePipeline = pipelines.extrudedTilePipeline
        globePipeline = pipelines.globePipeline
        starfield = pipelines.starfield

        textRenderer = TextRenderer(device: metal.device, library: metalLibrary)
        poiSpriteAtlas = PoiSpriteAtlas(device: metal.device)
        tilesTexture = TilesTexture(metalDevice: metal.device, tilePipeline: tilePipeline)
        debugOverlayRenderer = DebugOverlayRenderer(metalDevice: metal.device, settings: config.debug)
        camera = Camera()
        tileCulling = TileCulling(camera: camera)
        cameraControl = CameraControl(settings: config.camera)
        renderModeController = RenderModeController()
        RendererSetup.configureCamera(cameraControl)

        baseGridBuffers = RendererSetup.makeBaseGridBuffers(metalDevice: metal.device)
        flatTileOriginCalculator = FlatTileOriginCalculator(metalDevice: metal.device)

        globeCapRenderer = GlobeCapRenderer(metalDevice: metal.device,
                                            layer: layer,
                                            library: metalLibrary,
                                            maxLatitude: maxLatitude,
                                            mapBaseColors: mapBaseColors)

        tileRenderStore = TileRenderStore(mapStyle: mapStyle,
                                          metalDevice: metal.device,
                                          textRenderer: textRenderer,
                                          config: config)

        baseLabelCache = BaseLabelCache(metalDevice: metal.device)
        roadLabelCache = RoadLabelCache(metalDevice: metal.device,
                                        textRenderer: textRenderer)

        avatarsController = uiView.avatarsController
        avatarsRenderer = AvatarsRenderer(metalDevice: metal.device,
                                          layer: layer,
                                          library: metalLibrary,
                                          config: config.avatars)

        tileRenderStore.initRenderer(self)
    }

    func newTileAvailable(tile: Tile) {
        uiView.requestFrame()
    }

    @discardableResult
    func render(to layer: CAMetalLayer) -> Bool {
        guard let frameSlotIndex = inFlightFramePool.tryAcquire() else {
            recordSkippedFrame(reason: .inFlightSlotsExhausted)
            return false
        }

        let didSchedule = renderFrame(on: layer, frameSlotIndex: frameSlotIndex)
        if didSchedule == false {
            inFlightFramePool.release(slot: frameSlotIndex)
        }
        return didSchedule
    }

    private func renderFrame(on layer: CAMetalLayer, frameSlotIndex: Int) -> Bool {
        let collectStart = CACurrentMediaTime()
        guard let frameContext = collectInput(layer: layer, frameSlotIndex: frameSlotIndex) else {
            return false
        }
        frameContext.diagnostics.recordStage(.collectInput, duration: CACurrentMediaTime() - collectStart)

        measureStage(.updateScene, diagnostics: frameContext.diagnostics) {
            updateScene(frameContext: frameContext)
        }
        measureStage(.prepareGPU, diagnostics: frameContext.diagnostics) {
            prepareGPU(frameContext: frameContext)
        }
        let encodeStart = CACurrentMediaTime()
        let drawable = encodePasses(frameContext: frameContext, layer: layer)
        frameContext.diagnostics.recordStage(.encodePasses, duration: CACurrentMediaTime() - encodeStart)

        let presentStart = CACurrentMediaTime()
        let didSchedule = presentFrame(frameContext: frameContext,
                                       drawable: drawable,
                                       frameSlotIndex: frameSlotIndex)
        frameContext.diagnostics.recordStage(.presentFrame, duration: CACurrentMediaTime() - presentStart)
        let hasActiveLabelFadeAnimations = frameContext.sharedState.baseLabelState.hasActiveFadeAnimations
            || frameContext.sharedState.roadLabelState.hasActiveFadeAnimations
        let hasActiveLabelVisibilityCycle = frameContext.sharedState.baseLabelState.hasActiveVisibilityCycle
        let hasActiveAvatarAnimations = frameContext.sharedState.avatarState.hasActiveAnimations
        uiView.setLabelFadeRenderingActive(hasActiveLabelFadeAnimations)
        uiView.setLabelVisibilityCycleRenderingActive(hasActiveLabelVisibilityCycle)
        uiView.setAvatarAnimationRenderingActive(hasActiveAvatarAnimations)

        currentDiagnostics = frameContext.diagnostics
        #if DEBUG
        print(frameContext.diagnostics.summaryLine())
        #endif
        return didSchedule
    }

    private func collectInput(layer: CAMetalLayer, frameSlotIndex: Int) -> FrameContext? {
        let nowTime = Date().timeIntervalSince(startDate)
        frameIndex &+= 1
        let deltaTime = frameIndex <= 1 ? 0 : nowTime - previousFrameTime
        previousFrameTime = nowTime

        let diagnostics = FrameDiagnostics(frameIndex: frameIndex, frameTime: nowTime)
        let services = FrameContextServices(diagnostics: diagnostics)

        let drawSize = layer.drawableSize
        if drawSize.width == 0 || drawSize.height == 0 {
            diagnostics.recordSkipReason(.zeroDrawableSize)
            currentDiagnostics = diagnostics
            return nil
        }

        if drawSize != lastDrawableSize {
            let aspect = Float(drawSize.width) / Float(drawSize.height)
            camera.recalculateProjection(aspect: aspect)
            lastDrawableSize = drawSize
        }

        screenMatrix.update(drawSize)
        guard let screenMatrixValue = screenMatrix.get() else {
            diagnostics.recordSkipReason(.missingScreenMatrix)
            currentDiagnostics = diagnostics
            return nil
        }

        CameraUpdater.updateIfNeeded(camera: camera, cameraControl: cameraControl)

        guard let cameraMatrix = camera.cameraMatrix,
              let cameraView = camera.view else {
            diagnostics.recordSkipReason(.missingCameraState)
            currentDiagnostics = diagnostics
            return nil
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            diagnostics.recordSkipReason(.missingCommandBuffer)
            currentDiagnostics = diagnostics
            return nil
        }

        let resolvedPresentation = ViewModeCalculator.resolve(cameraState: cameraControl.cameraState,
                                                              settings: settings.presentation,
                                                              projectionPolicy: renderModeController.projectionPolicy,
                                                              visibilityPolicy: renderModeController.visibilityPolicy)
        transition = resolvedPresentation.transition
        let targetTileZoom = settings.tiles.resolvedCoverageZoomLevel(forCameraZoom: cameraControl.zoom)
        let visibleContent = tileCulling.resolveVisibleContent(cameraState: cameraControl.cameraState,
                                                               resolvedPresentation: resolvedPresentation,
                                                               targetZoom: targetTileZoom,
                                                               diagnostics: diagnostics)

        let matrices = FrameCameraMatrices(projectionView: cameraMatrix,
                                           view: cameraView,
                                           screen: screenMatrixValue)

        resourceRegistry.beginFrame(frameIndex: frameIndex)
        resourceRegistry.setPipeline(polygonPipeline.pipelineState, named: .polygonPipeline)
        resourceRegistry.setPipeline(tilePipeline.pipelineState, named: .tilePipeline)
        resourceRegistry.setPipeline(extrudedTilePipeline.pipelineState, named: .extrudedTilePipeline)
        resourceRegistry.setPipeline(extrudedTilePipeline.winnerPipelineState, named: .extrudedTileWinnerPipeline)
        resourceRegistry.setPipeline(globePipeline.pipelineState, named: .globePipeline)
        resourceRegistry.setTexture(textRenderer.texture, named: .labelGlyphAtlas)
        resourceRegistry.setTexture(poiSpriteAtlas.texture, named: .poiSpriteAtlas)

        return FrameContext(frameIndex: frameIndex,
                            frameSlotIndex: frameSlotIndex,
                            time: nowTime,
                            deltaTime: deltaTime,
                            drawSize: drawSize,
                            viewport: SIMD2<Float>(Float(drawSize.width), Float(drawSize.height)),
                            cameraMatrices: matrices,
                            cameraEye: camera.eye,
                            qualityTier: RenderQualityTier.from(zoom: cameraControl.zoom),
                            commandBuffer: commandBuffer,
                            drawable: nil,
                            services: services,
                            mapCameraState: cameraControl.cameraState,
                            resolvedPresentation: resolvedPresentation,
                            visibleContent: visibleContent,
                            diagnostics: diagnostics)
    }

    private func updateScene(frameContext: FrameContext) {
        subsystemRegistry.update(frameContext: frameContext)
    }

    private func prepareGPU(frameContext: FrameContext) {
        subsystemRegistry.prepareGPU(frameContext: frameContext, resourceRegistry: resourceRegistry)

        let counts = resourceRegistry.counts
        frameContext.services.diagnostics.setCounter(.resourceBufferCount, value: counts.buffers)
        frameContext.services.diagnostics.setCounter(.resourceTextureCount, value: counts.textures)
        frameContext.services.diagnostics.setCounter(.resourcePipelineCount, value: counts.pipelines)
    }

    private func encodePasses(frameContext: FrameContext, layer: CAMetalLayer) -> CAMetalDrawable? {
        guard let commandBuffer = frameContext.commandBuffer else {
            frameContext.services.diagnostics.recordSkipReason(.missingCommandBuffer)
            return nil
        }

        guard let drawable = layer.nextDrawable() else {
            frameContext.services.diagnostics.recordSkipReason(.missingDrawable)
            return nil
        }

        let clearColor = makeClearColor(transition: frameContext.transition)
        let depthTexture = ensureDepthTexture(drawSize: frameContext.drawSize)
        if let depthTexture {
            resourceRegistry.setTexture(depthTexture, named: .depthTexture)
        }
        if frameContext.renderBackendMode == .flat,
           let commandBuffer = frameContext.commandBuffer,
           let winnerIDTexture = ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
           let winnerDepthTexture = ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) {
            resourceRegistry.setTexture(winnerIDTexture, named: .buildingWinnerIDTexture)
            resourceRegistry.setTexture(winnerDepthTexture, named: .buildingWinnerDepthTexture)
            RendererSceneDrawer.drawExtrudedWinnerPass(commandBuffer: commandBuffer,
                                                       cameraUniform: frameContext.cameraUniform,
                                                       placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                                       flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                                       winnerIDTexture: winnerIDTexture,
                                                       winnerDepthTexture: winnerDepthTexture,
                                                       extrudedTilePipeline: extrudedTilePipeline,
                                                       extrudedDepthState: extrudedDepthState)
        }

        let renderEncoder = RendererPassEncoderFactory.makeRenderEncoder(commandBuffer: commandBuffer,
                                                                         drawable: drawable,
                                                                         clearColor: clearColor,
                                                                         depthTexture: depthTexture)

        let hasBaseLabels = baseLabelDrawSubsystemRef?.hasRenderableLabels ?? false
        let hasRoadLabels = roadLabelDrawSubsystemRef?.hasRenderableLabels ?? false
        let passAvailability = RenderPassAvailability(labelsEnabled: hasBaseLabels || hasRoadLabels,
                                                      avatarsEnabled: avatarSubsystemRef?.hasRenderableAvatars ?? false,
                                                      debugOverlayEnabled: shouldEncodeDebugOverlay())
        let passPlan = RenderPassPlanner.plan(availability: passAvailability)

        for planItem in passPlan {
            guard planItem.enabled else {
                if let reason = planItem.skipReason {
                    frameContext.services.diagnostics.recordSkipReason(reason)
                }
                continue
            }

            let passStart = CACurrentMediaTime()
            subsystemRegistry.encode(pass: planItem.pass,
                                     encoder: renderEncoder,
                                     frameContext: frameContext)
            frameContext.diagnostics.recordPass(planItem.pass,
                                                duration: CACurrentMediaTime() - passStart)
        }

        renderEncoder.endEncoding()
        return drawable
    }

    private func presentFrame(frameContext: FrameContext,
                              drawable: CAMetalDrawable?,
                              frameSlotIndex: Int) -> Bool {
        guard let commandBuffer = frameContext.commandBuffer,
              let drawable else {
            return false
        }

        let avatarSelectionSnapshot = frameContext.sharedState.avatarState.selectionSnapshot
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightFramePool.release(slot: frameSlotIndex)
            self?.uiView.updateAvatarSelectionSnapshot(avatarSelectionSnapshot)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    private func recordSkippedFrame(reason: RenderSkipReason) {
        let nowTime = Date().timeIntervalSince(startDate)
        frameIndex &+= 1
        previousFrameTime = nowTime

        let diagnostics = FrameDiagnostics(frameIndex: frameIndex, frameTime: nowTime)
        diagnostics.recordSkipReason(reason)
        diagnostics.recordStage(.collectInput, duration: 0)
        diagnostics.recordStage(.updateScene, duration: 0)
        diagnostics.recordStage(.prepareGPU, duration: 0)
        diagnostics.recordStage(.encodePasses, duration: 0)
        diagnostics.recordStage(.presentFrame, duration: 0)
        currentDiagnostics = diagnostics
        #if DEBUG
        print(diagnostics.summaryLine())
        #endif
    }

    private func measureStage(_ stage: FrameStage,
                              diagnostics: FrameDiagnostics,
                              block: () -> Void) {
        let start = CACurrentMediaTime()
        block()
        diagnostics.recordStage(stage, duration: CACurrentMediaTime() - start)
    }

    private func buildSubsystemRegistry() -> RenderSubsystemRegistry {
        let tileDemandPlacementSubsystem = TileDemandPlacementSubsystem(tileRenderStore: tileRenderStore,
                                                                        initialZoom: Int(cameraControl.zoom))

        let tileProjectionIndexSubsystem = TileProjectionIndexSubsystem(flatTileOriginCalculator: flatTileOriginCalculator)

        let tileGlobeTextureSubsystem = TileGlobeTextureSubsystem(tilesTexture: tilesTexture)

        let baseLabelSubsystem = BaseLabelPrepareSubsystem(baseLabelCache: baseLabelCache,
                                                           roadLabelCache: roadLabelCache,
                                                           metalDevice: metalDevice,
                                                           library: metalLibrary,
                                                           settings: settings.labels)
        let baseLabelDrawSubsystem = BaseLabelDrawSubsystem(textRenderer: textRenderer,
                                                            poiSpriteAtlas: poiSpriteAtlas,
                                                            metalDevice: metalDevice)
        let roadLabelDrawSubsystem = RoadLabelDrawSubsystem(textRenderer: textRenderer,
                                                            metalDevice: metalDevice)

        let avatarSubsystem = AvatarRenderSubsystem(avatarsRenderer: avatarsRenderer,
                                                    avatarsController: avatarsController,
                                                    depthDisabledState: depthDisabledState)

        let commonViewSceneSubsystem = CommonViewSceneRenderSubsystem(depthDisabledState: depthDisabledState)
        let globeViewSceneSubsystem = GlobeViewSceneRenderSubsystem(camera: camera,
                                                                    starfield: starfield,
                                                                    globeDepthState: extrudedDepthState,
                                                                    globeCapDepthState: globeCapDepthState,
                                                                    depthDisabledState: depthDisabledState,
                                                                    globeCapRenderer: globeCapRenderer,
                                                                    globePipeline: globePipeline,
                                                                    baseGridBuffers: baseGridBuffers,
                                                                    tilesTexture: tilesTexture)
        let flatViewSceneSubsystem = FlatViewSceneRenderSubsystem(tilePipeline: tilePipeline,
                                                                  separateRoadRenderingMinimumZoom: settings.style.flatSeparateRoadRenderingMinimumZoom,
                                                                  buildingExtrusionAlpha: settings.style.buildingExtrusionAlpha,
                                                                  buildingWinnerIDTextureProvider: { [weak self] in
                                                                      self?.buildingWinnerIDTexture
                                                                  },
                                                                  extrudedTilePipeline: extrudedTilePipeline,
                                                                  extrudedColorPassDepthState: extrudedColorPassDepthState,
                                                                  depthDisabledState: depthDisabledState)

        let debugSubsystem = DebugOverlayRenderSubsystem(polygonPipeline: polygonPipeline,
                                                         debugOverlayRenderer: debugOverlayRenderer,
                                                         textRenderer: textRenderer,
                                                         cameraControl: cameraControl)

        tileGlobeTextureSubsystemRef = tileGlobeTextureSubsystem
        baseLabelDrawSubsystemRef = baseLabelDrawSubsystem
        roadLabelDrawSubsystemRef = roadLabelDrawSubsystem
        avatarSubsystemRef = avatarSubsystem
        
        return RenderSubsystemRegistry(subsystems: [tileDemandPlacementSubsystem,
                                                    tileProjectionIndexSubsystem,
                                                    tileGlobeTextureSubsystem,
                                                    baseLabelSubsystem,
                                                    baseLabelDrawSubsystem,
                                                    roadLabelDrawSubsystem,
                                                    avatarSubsystem,
                                                    commonViewSceneSubsystem,
                                                    globeViewSceneSubsystem,
                                                    flatViewSceneSubsystem,
                                                    debugSubsystem
                                                   ])
    }

    static func shouldEncodeDebugOverlay(debugSettings: MapSettings.DebugSettings) -> Bool {
        guard debugSettings.overlayEnabled || debugSettings.tileOverlayEnabled else {
            return false
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private func shouldEncodeDebugOverlay() -> Bool {
        Self.shouldEncodeDebugOverlay(debugSettings: settings.debug)
    }

    static func makeSceneDepthDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true
        return descriptor
    }

    static func makeGlobeCapDepthDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = false
        return descriptor
    }

    static func makeTransparentExtrudedDepthDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = false
        return descriptor
    }

    static func makeDepthDisabledDescriptor() -> MTLDepthStencilDescriptor {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false
        return descriptor
    }

    private func makeClearColor(transition: Float) -> MTLClearColor {
        let transitionMix = Double(transition)
        let spaceColor = settings.scene.space.clearColor
        let mapColor = settings.scene.mapClearColor
        let clearColorValue = spaceColor + (mapColor - spaceColor) * transitionMix
        return MTLClearColor(red: clearColorValue.x,
                             green: clearColorValue.y,
                             blue: clearColorValue.z,
                             alpha: clearColorValue.w)
    }

    private func ensureDepthTexture(drawSize: CGSize) -> MTLTexture? {
        let width = Int(drawSize.width)
        let height = Int(drawSize.height)
        guard width > 0, height > 0 else { return nil }

        if let depthTexture = depthTexture,
           depthTexture.width == width,
           depthTexture.height == height {
            return depthTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let newTexture = metalDevice.makeTexture(descriptor: descriptor)
        newTexture?.label = RenderResourceName.depthTexture.rawValue
        depthTexture = newTexture
        return newTexture
    }

    private func ensureBuildingWinnerIDTexture(drawSize: CGSize) -> MTLTexture? {
        let width = Int(drawSize.width)
        let height = Int(drawSize.height)
        guard width > 0, height > 0 else { return nil }

        if let buildingWinnerIDTexture,
           buildingWinnerIDTexture.width == width,
           buildingWinnerIDTexture.height == height {
            return buildingWinnerIDTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let newTexture = metalDevice.makeTexture(descriptor: descriptor)
        newTexture?.label = RenderResourceName.buildingWinnerIDTexture.rawValue
        buildingWinnerIDTexture = newTexture
        return newTexture
    }

    private func ensureBuildingWinnerDepthTexture(drawSize: CGSize) -> MTLTexture? {
        let width = Int(drawSize.width)
        let height = Int(drawSize.height)
        guard width > 0, height > 0 else { return nil }

        if let buildingWinnerDepthTexture,
           buildingWinnerDepthTexture.width == width,
           buildingWinnerDepthTexture.height == height {
            return buildingWinnerDepthTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let newTexture = metalDevice.makeTexture(descriptor: descriptor)
        newTexture?.label = RenderResourceName.buildingWinnerDepthTexture.rawValue
        buildingWinnerDepthTexture = newTexture
        return newTexture
    }

    func switchRenderMode() {
        let resolvedPresentation = ViewModeCalculator.resolve(cameraState: cameraControl.cameraState,
                                                              settings: settings.presentation,
                                                              projectionPolicy: renderModeController.projectionPolicy,
                                                              visibilityPolicy: renderModeController.visibilityPolicy)
        renderModeController.advanceProjectionPolicy(currentResolvedPresentation: resolvedPresentation)
        applyCameraConstraints()
    }

    func setVisibilityPolicy(_ policy: VisibilityPolicy) {
        renderModeController.setVisibilityPolicy(policy)
    }

    func rotateCameraYaw(delta: Float) {
        cameraControl.rotateYaw(delta: delta)
        applyCameraBearingConstraint()
    }

    func panCamera(deltaX: Double, deltaY: Double) {
        cameraControl.pan(deltaX: deltaX, deltaY: deltaY)
    }

    func zoomCamera(scale: Double, velocity: Double = 0) {
        cameraControl.zoom(scale: scale, velocity: velocity)
        applyCameraConstraints()
    }

    func zoomCamera(delta: Double) {
        cameraControl.zoom(delta: delta)
        applyCameraConstraints()
    }

    func setCameraPitch(_ pitch: Float) {
        cameraControl.setPitch(pitch)
        applyCameraPitchConstraint()
    }

    func setCameraPosition(_ cameraPosition: ImmersiveMapCameraPosition) {
        cameraControl.setCameraPosition(cameraPosition)
        applyCameraConstraints()
    }

    func setCameraState(_ cameraState: MapCameraState) {
        cameraControl.setCameraState(cameraState)
        applyCameraConstraints()
    }

    func currentVisibilityPolicy() -> VisibilityPolicy {
        renderModeController.visibilityPolicy
    }

    func isSphericalRenderBackendActive() -> Bool {
        let resolvedPresentation = ViewModeCalculator.resolve(cameraState: cameraControl.cameraState,
                                                              settings: settings.presentation,
                                                              projectionPolicy: renderModeController.projectionPolicy,
                                                              visibilityPolicy: renderModeController.visibilityPolicy)
        return resolvedPresentation.renderBackendMode == .spherical
    }

    func currentCameraPosition() -> ImmersiveMapCameraPosition {
        let latLon = cameraControl.getLatLonDeg()
        return ImmersiveMapCameraPosition(latitudeDegrees: latLon.latDeg,
                                          longitudeDegrees: latLon.lonDeg,
                                          zoom: cameraControl.zoom,
                                          bearing: cameraControl.yaw,
                                          pitch: cameraControl.pitch)
    }

    func currentCameraState() -> MapCameraState {
        cameraControl.currentCameraState()
    }

    func applySettings(_ settings: MapSettings) {
        self.settings = settings
        cameraControl.apply(settings: settings.camera)
        applyCameraConstraints()
        debugOverlayRenderer.apply(settings: settings.debug)
    }

    func currentMaximumPitch() -> Float {
        cameraPitchConstraint().maximumPitch
    }

    private func applyCameraConstraints() {
        applyCameraBearingConstraint()
        applyCameraPitchConstraint()
    }

    private func applyCameraBearingConstraint() {
        cameraControl.clampBearing(to: cameraBearingConstraint())
    }

    private func applyCameraPitchConstraint() {
        cameraControl.clampPitch(to: cameraPitchConstraint())
    }

    private func cameraBearingConstraint() -> CameraBearingConstraint {
        CameraBearingConstraintResolver.resolve(cameraState: cameraControl.cameraState,
                                               settings: settings,
                                               projectionPolicy: renderModeController.projectionPolicy,
                                               visibilityPolicy: renderModeController.visibilityPolicy)
    }

    private func cameraPitchConstraint() -> CameraPitchConstraint {
        CameraPitchConstraintResolver.resolve(cameraState: cameraControl.cameraState,
                                             settings: settings,
                                             projectionPolicy: renderModeController.projectionPolicy,
                                             visibilityPolicy: renderModeController.visibilityPolicy)
    }

    func handleMemoryWarning() {
        subsystemRegistry.handleMemoryWarning()
        depthTexture = nil
        buildingWinnerIDTexture = nil
        buildingWinnerDepthTexture = nil
    }
}
