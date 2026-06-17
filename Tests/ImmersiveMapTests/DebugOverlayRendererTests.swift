// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class DebugOverlayRendererTests: XCTestCase {
    func testDebugPanelHudDoesNotRequireMetalDebugPass() {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        let controls = DebugOverlayControlState()

        XCTAssertFalse(RenderDebugOverlayPolicy.shouldEncode(settings, controls: controls.snapshot()))
    }

    func testTileLayerDebugRequiresMetalDebugPass() {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        let controls = DebugOverlayControlState()
        controls.setTileLayersEnabled(true)

        XCTAssertTrue(RenderDebugOverlayPolicy.shouldEncode(settings, controls: controls.snapshot()))
    }

    func testAxesDebugRequiresMetalDebugPass() {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        let controls = DebugOverlayControlState()
        controls.setAxesEnabled(true)

        XCTAssertTrue(RenderDebugOverlayPolicy.shouldEncode(settings, controls: controls.snapshot()))
    }

    func testWireframeDebugDoesNotRequireMetalDebugPass() {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        let controls = DebugOverlayControlState()
        controls.setWireframeEnabled(true)

        XCTAssertFalse(RenderDebugOverlayPolicy.shouldEncode(settings, controls: controls.snapshot()))
    }

    func testDebugControlsDoNotEncodeWhenPanelIsDisabled() {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = false
        let controls = DebugOverlayControlState()
        controls.setAxesEnabled(true)
        controls.setTileLayersEnabled(true)
        controls.setWireframeEnabled(true)

        XCTAssertFalse(RenderDebugOverlayPolicy.shouldEncode(settings, controls: controls.snapshot()))
    }

    func testHudSnapshotIsNilWhenDebugPanelIsDisabled() {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = false

        let snapshot = DebugOverlayHUDSnapshot.make(
            settings: settings,
            zoom: 4,
            latitude: 55,
            longitude: 37,
            cameraDebugLines: [],
            diagnostics: nil
        )

        XCTAssertNil(snapshot)
    }

    func testHudSnapshotIncludesCoordinatesAndDiagnosticsLines() {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        let diagnostics = FrameDiagnostics(frameIndex: 42, frameTime: 16.7)

        let snapshot = DebugOverlayHUDSnapshot.make(
            settings: settings,
            zoom: 5.412,
            latitude: 55.7558,
            longitude: 37.6173,
            cameraDebugLines: ["camera z:5.41 pitch:36.00 bearing:18.00"],
            diagnostics: diagnostics
        )

        XCTAssertEqual(snapshot?.coordinateLines.zoom, "z: 5.41")
        XCTAssertEqual(snapshot?.coordinateLines.latLon, "lat: 55.756 lon: 37.617")
        XCTAssertEqual(snapshot?.diagnosticsLines.first, "camera z:5.41 pitch:36.00 bearing:18.00")
        XCTAssertTrue(snapshot?.diagnosticsLines.contains { $0.hasPrefix("frame: 42") } == true)
    }

    func testHudSnapshotIncludesAtlasPagesWhenSummaryExists() throws {
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        let summary = GlobeAtlasDebugSummary(plan: try makeSingleAllocationAtlasPlan())

        let snapshot = DebugOverlayHUDSnapshot.make(
            settings: settings,
            zoom: 5.412,
            latitude: 55.7558,
            longitude: 37.6173,
            cameraDebugLines: [],
            diagnostics: nil,
            atlasDebugSummary: summary
        )

        XCTAssertEqual(snapshot?.atlasPages.count, 1)
        XCTAssertEqual(snapshot?.atlasPages[0].allocations.first?.targetTile, Tile(x: 0, y: 0, z: 1))
    }

    func testOverlayDiagnosticsIncludeCameraLinesWithoutFrameDiagnostics() {
        let lines = DebugOverlayRenderer.makeOverlayDiagnosticsTextLines(
            cameraDebugLines: ["camera z:5.41 pitch:36.00 bearing:18.00"],
            diagnostics: nil
        )

        XCTAssertEqual(lines, ["camera z:5.41 pitch:36.00 bearing:18.00"])
    }

    func testOverlayDiagnosticsPrependCameraLinesBeforeFrameDiagnostics() {
        let diagnostics = FrameDiagnostics(frameIndex: 42, frameTime: 16.7)

        let lines = DebugOverlayRenderer.makeOverlayDiagnosticsTextLines(
            cameraDebugLines: ["camera z:5.41 pitch:36.00 bearing:18.00"],
            diagnostics: diagnostics
        )

        XCTAssertEqual(lines.first, "camera z:5.41 pitch:36.00 bearing:18.00")
        XCTAssertTrue(lines.contains { $0.hasPrefix("frame: 42") })
    }

    func testOverlayDiagnosticsIncludeRamUsageWhenAvailable() {
        let diagnostics = FrameDiagnostics(frameIndex: 42, frameTime: 16.7)

        let lines = DebugOverlayRenderer.makeOverlayDiagnosticsTextLines(
            cameraDebugLines: [],
            diagnostics: diagnostics,
            memorySnapshot: ProcessMemorySnapshot(physicalFootprintBytes: 128 * 1024 * 1024)
        )

        XCTAssertTrue(lines.contains("memory ram:128.0MB"))
    }

    private func makeSingleAllocationAtlasPlan() throws -> GlobeAtlasPlan {
        let sourceTile = Tile(x: 0, y: 0, z: 1)
        let targetTile = Tile(x: 0, y: 0, z: 1)
        let metalTile = MetalTile(tile: sourceTile, tileBuffers: try makeTileBuffers())
        let placeTile = PlaceTile(metalTile: metalTile,
                                  placeIn: VisibleTile(tile: targetTile),
                                  lodKind: .exact)
        let candidate = GlobeAtlasCandidate(placementIndex: 0,
                                            placeTile: placeTile,
                                            screenDemandPx: 128,
                                            distanceToCamera: 0,
                                            desiredDepth: .depth4)
        let allocation = GlobeAtlasAllocation(candidate: candidate,
                                              pageIndex: 0,
                                              placedPosition: PlacedPos(depth: 4, x: 0, y: 0),
                                              atlasDepth: .depth4,
                                              cellSizePx: 256)
        return GlobeAtlasPlan(allocations: [allocation],
                              pageSummaries: [GlobeAtlasPageSummary(pageIndex: 0, allocatedSlotCount: 1)],
                              downgradedAllocationCount: 0,
                              skippedAllocationCount: 0)
    }

    private func makeTileBuffers() throws -> TileBuffers {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is required for MetalTile test fixture.")
        }
        let value: UInt32 = 0
        let buffer = device.makeBuffer(bytes: [value], length: MemoryLayout<UInt32>.stride)!
        let ground = TileBuffers.GeometryLayer(verticesBuffer: buffer,
                                               indicesBuffer: buffer,
                                               stylesBuffer: buffer,
                                               overviewStyleMaskBuffer: buffer,
                                               indicesCount: 0,
                                               verticesCount: 0)
        let extruded = TileBuffers.Extruded(verticesBuffer: buffer,
                                            indicesBuffer: buffer,
                                            stylesBuffer: buffer,
                                            indicesCount: 0,
                                            verticesCount: 0)
        let phases = RoadGeometryPhases(shadow: ground,
                                        casing: ground,
                                        fill: ground,
                                        detail: ground,
                                        overlay: ground)
        let roads = RoadStructureBuckets(tunnel: phases,
                                         ground: phases,
                                         bridge: phases)
        return TileBuffers(ground: ground,
                           roads: roads,
                           bridgeOverlay: ground,
                           extruded: extruded,
                           textLabels: TileBuffers.TextLabels(placementInputs: [],
                                                               labelsByStyleRuns: [],
                                                               poiIconRuns: []),
                           roadLabels: TileBuffers.RoadLabels(pathInputs: [],
                                                              pathRanges: [],
                                                              pathLabels: [],
                                                              labelStyle: nil,
                                                              localGlyphVerticesBuffer: nil,
                                                              localGlyphVertexCount: 0,
                                                              glyphBounds: [],
                                                              glyphBoundRanges: [],
                                                              sizes: [],
                                                              anchorRanges: [],
                                                              anchors: []))
    }
}
