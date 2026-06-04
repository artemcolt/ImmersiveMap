// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import MetalKit
import QuartzCore

final class RenderFrameEngine {
    private var settings: ImmersiveMapSettings
    private let resources: RenderStaticResources
    private let cameraCoordinator: ImmersiveMapCameraCoordinator
    private let attachments: FrameAttachmentStore
    private let subsystemGraph: RenderSubsystemGraph
    private let eventSink: RenderFrameEventSink
    private let inFlightFramePool = InFlightFramePool(slotsCount: InFlightFramePool.inFlightFramesCount)
    private let startDate = Date()
    private var frameIndex: UInt64 = 0
    private var previousFrameTime: TimeInterval = 0

    private(set) var currentDiagnostics: FrameDiagnostics?

    init(settings: ImmersiveMapSettings,
         resources: RenderStaticResources,
         cameraCoordinator: ImmersiveMapCameraCoordinator,
         eventSink: RenderFrameEventSink) {
        self.settings = settings
        self.resources = resources
        self.cameraCoordinator = cameraCoordinator
        self.attachments = FrameAttachmentStore(metalDevice: resources.metalContext.device)
        self.eventSink = eventSink
        self.subsystemGraph = RenderSubsystemGraph(resources: resources,
                                                   settings: settings,
                                                   initialZoom: Int(cameraCoordinator.currentCameraState().zoom),
                                                   buildingWinnerIDTextureProvider: { [attachments] in
                                                       attachments.currentBuildingWinnerIDTexture
                                                   })
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

    func applySettings(_ settings: ImmersiveMapSettings) {
        self.settings = settings
    }

    func handleMemoryWarning() {
        subsystemGraph.handleMemoryWarning()
        attachments.reset()
    }

    private func renderFrame(on layer: CAMetalLayer, frameSlotIndex: Int) -> Bool {
        let collectStart = CACurrentMediaTime()
        guard let frameContext = collectInput(layer: layer, frameSlotIndex: frameSlotIndex) else {
            return false
        }
        frameContext.diagnostics.recordStage(.collectInput, duration: CACurrentMediaTime() - collectStart)

        measureStage(.updateScene, diagnostics: frameContext.diagnostics) {
            subsystemGraph.update(frameContext: frameContext)
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
        eventSink.applyActivityState(RenderActivityState(labelFadeRenderingActive: hasActiveLabelFadeAnimations,
                                                         labelVisibilityCycleRenderingActive: hasActiveLabelVisibilityCycle,
                                                         avatarAnimationRenderingActive: hasActiveAvatarAnimations))

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

        guard let cameraFrameState = cameraCoordinator.makeFrameState(drawSize: layer.drawableSize,
                                                                      diagnostics: diagnostics) else {
            currentDiagnostics = diagnostics
            return nil
        }

        guard let commandBuffer = resources.metalContext.makeCommandBuffer() else {
            diagnostics.recordSkipReason(.missingCommandBuffer)
            currentDiagnostics = diagnostics
            return nil
        }

        publishStaticResources(frameIndex: frameIndex)

        return FrameContext(frameIndex: frameIndex,
                            frameSlotIndex: frameSlotIndex,
                            time: nowTime,
                            deltaTime: deltaTime,
                            drawSize: cameraFrameState.drawSize,
                            viewport: cameraFrameState.viewport,
                            cameraMatrices: cameraFrameState.cameraMatrices,
                            cameraEye: cameraFrameState.cameraEye,
                            qualityTier: cameraFrameState.qualityTier,
                            commandBuffer: commandBuffer,
                            drawable: nil,
                            services: services,
                            mapCameraState: cameraFrameState.mapCameraState,
                            resolvedPresentation: cameraFrameState.resolvedPresentation,
                            visibleContent: cameraFrameState.visibleContent,
                            diagnostics: diagnostics)
    }

    private func publishStaticResources(frameIndex: UInt64) {
        let resourceRegistry = subsystemGraph.resourceRegistry
        resourceRegistry.beginFrame(frameIndex: frameIndex)
        resourceRegistry.setPipeline(resources.polygonPipeline.pipelineState, named: .polygonPipeline)
        resourceRegistry.setPipeline(resources.tilePipeline.pipelineState, named: .tilePipeline)
        resourceRegistry.setPipeline(resources.extrudedTilePipeline.pipelineState, named: .extrudedTilePipeline)
        resourceRegistry.setPipeline(resources.extrudedTilePipeline.winnerPipelineState, named: .extrudedTileWinnerPipeline)
        resourceRegistry.setPipeline(resources.globePipeline.pipelineState, named: .globePipeline)
        resourceRegistry.setTexture(resources.textRenderer.texture, named: .labelGlyphAtlas)
        resourceRegistry.setTexture(resources.poiSpriteAtlas.texture, named: .poiSpriteAtlas)
    }

    private func prepareGPU(frameContext: FrameContext) {
        subsystemGraph.prepareGPU(frameContext: frameContext)

        let counts = subsystemGraph.resourceRegistry.counts
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

        let resourceRegistry = subsystemGraph.resourceRegistry
        let clearColor = makeClearColor(transition: frameContext.transition)
        let depthTexture = attachments.ensureDepthTexture(drawSize: frameContext.drawSize)
        if let depthTexture {
            resourceRegistry.setTexture(depthTexture, named: .depthTexture)
        }
        if frameContext.renderBackendMode == .flat,
           let winnerIDTexture = attachments.ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
           let winnerDepthTexture = attachments.ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) {
            resourceRegistry.setTexture(winnerIDTexture, named: .buildingWinnerIDTexture)
            resourceRegistry.setTexture(winnerDepthTexture, named: .buildingWinnerDepthTexture)
            RendererSceneDrawer.drawExtrudedWinnerPass(commandBuffer: commandBuffer,
                                                       cameraUniform: frameContext.cameraUniform,
                                                       placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                                       flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                                       winnerIDTexture: winnerIDTexture,
                                                       winnerDepthTexture: winnerDepthTexture,
                                                       extrudedTilePipeline: resources.extrudedTilePipeline,
                                                       extrudedDepthState: resources.extrudedDepthState)
        }

        let renderEncoder = RendererPassEncoderFactory.makeRenderEncoder(commandBuffer: commandBuffer,
                                                                         drawable: drawable,
                                                                         clearColor: clearColor,
                                                                         depthTexture: depthTexture)
        let availability = subsystemGraph.passAvailability
        let passAvailability = RenderPassAvailability(labelsEnabled: availability.labelsEnabled,
                                                      avatarsEnabled: availability.avatarsEnabled,
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
            subsystemGraph.encode(pass: planItem.pass,
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
            self?.eventSink.updateAvatarSelectionSnapshot(avatarSelectionSnapshot)
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

    private func shouldEncodeDebugOverlay() -> Bool {
        Self.shouldEncodeDebugOverlay(debugSettings: settings.debug)
    }

    private static func shouldEncodeDebugOverlay(debugSettings: ImmersiveMapSettings.DebugSettings) -> Bool {
        guard debugSettings.overlayEnabled || debugSettings.tileOverlayEnabled else {
            return false
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
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
}
