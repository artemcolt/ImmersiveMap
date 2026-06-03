// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import MetalKit
import simd

enum RendererDebugOverlayDrawer {
    static func draw(renderEncoder: MTLRenderCommandEncoder,
                     frameContext: FrameContext,
                     polygonPipeline: PolygonsPipeline,
                     debugOverlayRenderer: DebugOverlayRenderer,
                     textRenderer: TextRenderer) {
        if debugOverlayRenderer.overlayEnabled {
            debugOverlayRenderer.drawAxes(renderEncoder: renderEncoder,
                                          polygonPipeline: polygonPipeline,
                                          cameraUniform: frameContext.cameraUniform)

            let cameraPosition = frameContext.mapCameraState.cameraPosition()
            #if DEBUG
            let diagnosticsOverlay: FrameDiagnostics? = frameContext.diagnostics
            #else
            let diagnosticsOverlay: FrameDiagnostics? = nil
            #endif

            debugOverlayRenderer.drawOverlayText(renderEncoder: renderEncoder,
                                                 textRenderer: textRenderer,
                                                 screenMatrix: frameContext.cameraMatrices.screen,
                                                 frameSlotIndex: frameContext.frameSlotIndex,
                                                 drawSize: frameContext.drawSize,
                                                 zoom: frameContext.mapCameraState.zoom,
                                                 latitude: cameraPosition.latitudeDegrees,
                                                 longitude: cameraPosition.longitudeDegrees,
                                                 diagnostics: diagnosticsOverlay)
        }

        if debugOverlayRenderer.tileOverlayEnabled {
            debugOverlayRenderer.drawTileOverlay(renderEncoder: renderEncoder,
                                                 polygonPipeline: polygonPipeline,
                                                 textRenderer: textRenderer,
                                                 frameContext: frameContext,
                                                 placeTiles: frameContext.sharedState.placeTileTrackingState.placeTiles)
        }
    }
}
