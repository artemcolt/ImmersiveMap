// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class BuildingWinnerPrePass: RenderFramePrePass {
    let name: String = "BuildingWinner"

    private let extrudedTilePipeline: ExtrudedTilePipeline
    private let extrudedDepthState: MTLDepthStencilState

    private var winnerIDTexture: MTLTexture?
    private var winnerDepthTexture: MTLTexture?

    init(extrudedTilePipeline: ExtrudedTilePipeline,
         extrudedDepthState: MTLDepthStencilState) {
        self.extrudedTilePipeline = extrudedTilePipeline
        self.extrudedDepthState = extrudedDepthState
    }

    func prepare(frameContext: FrameContext,
                 attachments: FrameAttachmentStore,
                 resourceRegistry: RenderResourceRegistry) {
        guard frameContext.renderSurfaceMode == .flat,
              let nextWinnerIDTexture = attachments.ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
              let nextWinnerDepthTexture = attachments.ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) else {
            winnerIDTexture = nil
            winnerDepthTexture = nil
            return
        }

        winnerIDTexture = nextWinnerIDTexture
        winnerDepthTexture = nextWinnerDepthTexture
        resourceRegistry.setTexture(nextWinnerIDTexture, named: .buildingWinnerIDTexture)
        resourceRegistry.setTexture(nextWinnerDepthTexture, named: .buildingWinnerDepthTexture)
    }

    func encode(commandBuffer: MTLCommandBuffer,
                frameContext: FrameContext) {
        guard frameContext.renderSurfaceMode == .flat,
              let winnerIDTexture,
              let winnerDepthTexture else {
            return
        }

        RendererSceneDrawer.drawExtrudedWinnerPass(commandBuffer: commandBuffer,
                                                   cameraUniform: frameContext.cameraUniform,
                                                   placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                                   flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                                   winnerIDTexture: winnerIDTexture,
                                                   winnerDepthTexture: winnerDepthTexture,
                                                   extrudedTilePipeline: extrudedTilePipeline,
                                                   extrudedDepthState: extrudedDepthState)
    }

    func handleMemoryWarning() {
        resetFrameTextures()
    }

    func evict() {
        resetFrameTextures()
    }

    private func resetFrameTextures() {
        winnerIDTexture = nil
        winnerDepthTexture = nil
    }
}
