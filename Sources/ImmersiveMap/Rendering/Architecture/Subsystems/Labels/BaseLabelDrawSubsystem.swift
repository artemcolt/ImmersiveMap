//
//  BaseLabelDrawSubsystem.swift
//  ImmersiveMapFramework
//

import Metal

final class BaseLabelDrawSubsystem: RenderSubsystem {
    let name: String = "BaseLabelDraw"

    private let textRenderer: TextRenderer
    private let poiSpriteAtlas: PoiSpriteAtlas

    private(set) var hasRenderableLabels: Bool = false

    init(textRenderer: TextRenderer,
         poiSpriteAtlas: PoiSpriteAtlas,
         metalDevice _: MTLDevice) {
        self.textRenderer = textRenderer
        self.poiSpriteAtlas = poiSpriteAtlas
    }

    func update(frameContext: FrameContext) {
        hasRenderableLabels = frameContext.sharedState.baseLabelState.labelInputsCount > 0
    }

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {
        if let labelRuntimeMetaBuffer = frameContext.sharedState.baseLabelState.labelRuntimeMetaBuffer {
            resourceRegistry.setBuffer(labelRuntimeMetaBuffer, named: .baseLabelRuntimeBuffer)
        }
    }

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard pass == .labels else {
            return
        }

        let baseLabelState = frameContext.sharedState.baseLabelState
        let labelCount = baseLabelState.labelInputsCount
        let activeLabelSpanCount = baseLabelState.activeLabelSpanCount
        guard labelCount > 0, activeLabelSpanCount > 0 else {
            return
        }

        guard let labelRuntimeMetaBuffer = baseLabelState.labelRuntimeMetaBuffer else {
            return
        }

        guard let screenPositionsBuffer = baseLabelState.screenPositionsBuffer,
              let collisionFlagsBuffer = baseLabelState.collisionFlagsBuffer else {
            return
        }

        RendererLabelDrawer.drawBaseLabels(renderEncoder: encoder,
                                           screenMatrix: frameContext.cameraMatrices.screen,
                                           textRenderer: textRenderer,
                                           poiSpriteAtlas: poiSpriteAtlas,
                                           screenPositionsBuffer: screenPositionsBuffer,
                                           collisionFlagsBuffer: collisionFlagsBuffer,
                                           labelRuntimeMetaBuffer: labelRuntimeMetaBuffer,
                                           baseLabelsDrawBatches: baseLabelState.baseLabelsDrawBatches)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
