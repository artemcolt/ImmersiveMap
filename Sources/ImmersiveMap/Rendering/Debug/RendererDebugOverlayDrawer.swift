//
//  RendererDebugOverlayDrawer.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/10/26.
//

import Foundation
import Metal
import MetalKit
import simd

enum RendererDebugOverlayDrawer {
    static func draw(renderEncoder: MTLRenderCommandEncoder,
                     frameContext: FrameContext,
                     polygonPipeline: PolygonsPipeline,
                     debugOverlayRenderer: DebugOverlayRenderer,
                     textRenderer: TextRenderer,
                     cameraControl: CameraControl) {
        if debugOverlayRenderer.overlayEnabled {
            debugOverlayRenderer.drawAxes(renderEncoder: renderEncoder,
                                          polygonPipeline: polygonPipeline,
                                          cameraUniform: frameContext.cameraUniform)

            let latLon = cameraControl.getLatLonDeg()
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
                                                 zoom: cameraControl.zoom,
                                                 latitude: latLon.latDeg,
                                                 longitude: latLon.lonDeg,
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
