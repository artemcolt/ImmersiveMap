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
                                                 cameraDebugLines: makeCameraDebugLines(frameContext: frameContext),
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

    private static func makeCameraDebugLines(frameContext: FrameContext) -> [String] {
        let cameraState = frameContext.mapCameraState
        let pitchDegrees = Double(cameraState.pitch) * 180.0 / Double.pi
        let bearingDegrees = Double(cameraState.bearing) * 180.0 / Double.pi
        let surface = frameContext.renderSurfaceMode == .spherical ? "globe" : "flat"
        let viewport = frameContext.viewport
        let eye = frameContext.cameraEye
        let placeTiles = frameContext.sharedState.placeTileTrackingState.placeTiles
        let sourceZoomCounts = zoomCountsLine(title: "srcZ", tiles: placeTiles.map { $0.metalTile.tile })
        let targetZoomCounts = zoomCountsLine(title: "targetZ", tiles: placeTiles.map { $0.placeIn.tile })

        return [
            "camera z:\(format(cameraState.zoom)) pitch:\(format(pitchDegrees)) bearing:\(format(bearingDegrees))",
            "surface:\(surface) transition:\(format(Double(frameContext.transition))) viewport:\(Int(viewport.x))x\(Int(viewport.y))",
            "eye x:\(format(Double(eye.x))) y:\(format(Double(eye.y))) z:\(format(Double(eye.z)))",
            targetZoomCounts,
            sourceZoomCounts
        ] + makeAtlasDebugLines(summary: frameContext.sharedState.globeAtlasDebugSummary)
    }

    static func makeAtlasDebugLines(summary: GlobeAtlasDebugSummary?) -> [String] {
        guard let summary else { return [] }

        let depthCounts = GlobeAtlasSlotDepth.allCases
            .map { "d\($0.rawValue):\(summary.slotCount(depth: $0))" }
            .joined(separator: " ")
        return [
            "atlas pages:\(summary.pageCount) alloc:\(summary.allocationCount) down:\(summary.downgradedAllocationCount) skip:\(summary.skippedAllocationCount)",
            "atlas \(depthCounts)"
        ]
    }

    private static func zoomCountsLine(title: String, tiles: [Tile]) -> String {
        let counts = Dictionary(grouping: tiles, by: \.z)
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "z\($0.key):\($0.value)" }
            .joined(separator: " ")
        return "\(title): \(counts.isEmpty ? "none" : counts)"
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}
