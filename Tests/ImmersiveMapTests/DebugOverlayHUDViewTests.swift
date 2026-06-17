// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

@testable import ImmersiveMap
import UIKit
import XCTest

@MainActor
final class DebugOverlayHUDViewTests: XCTestCase {
    func testSurfaceModeControlInvokesCallback() {
        let view = DebugOverlayHUDView()
        var didRequestSurfaceSwitch = false
        view.onSurfaceModeSwitchRequested = {
            didRequestSurfaceSwitch = true
        }

        view.simulateSurfaceModeSwitchForTesting()

        XCTAssertTrue(didRequestSurfaceSwitch)
    }

    func testAtlasTabDisplaysAtlasSnapshotPages() {
        let view = DebugOverlayHUDView()
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        view.apply(isDebugPanelEnabled: true,
                   controls: DebugOverlayControlSnapshot(axesEnabled: false,
                                                         tileLayersEnabled: false,
                                                         wireframeEnabled: false))
        view.apply(snapshot: DebugOverlayHUDSnapshot(
            coordinateLines: DebugOverlayCoordinateLines(zoom: "z: 1.00", latLon: "lat: 0.000 lon: 0.000"),
            diagnosticsLines: [],
            atlasPages: [
                GlobeAtlasDebugPage(pageIndex: 0,
                                    allocations: [
                                        GlobeAtlasDebugAllocation(pageIndex: 0,
                                                                  slotColumn: 0,
                                                                  slotRow: 0,
                                                                  slotsPerSide: 4,
                                                                  cellSizePx: 1024,
                                                                  atlasDepth: .depth2,
                                                                  sourceTile: Tile(x: 0, y: 0, z: 2),
                                                                  targetTile: Tile(x: 0, y: 0, z: 2),
                                                                  screenDemandPx: 512,
                                                                  isFallback: false)
                                    ])
            ],
            coordinateScale: settings.coordinateScale,
            diagnosticsScale: settings.diagnosticsScale,
            leftPadding: settings.leftPadding,
            topPadding: settings.topPadding,
            sectionSpacing: settings.sectionSpacing,
            textColor: settings.textColor
        ))

        view.simulateAtlasTabSelectionForTesting()

        XCTAssertTrue(view.isAtlasTabSelectedForTesting)
        XCTAssertEqual(view.atlasPreviewPageCountForTesting, 1)
    }

    func testAtlasTabCapsPanelHeightWhenManyAtlasPagesAreVisible() {
        let view = DebugOverlayHUDView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        view.apply(isDebugPanelEnabled: true,
                   controls: DebugOverlayControlSnapshot(axesEnabled: false,
                                                         tileLayersEnabled: false,
                                                         wireframeEnabled: false))
        view.apply(snapshot: makeSnapshot(settings: settings,
                                          atlasPages: (0..<12).map(makeAtlasPage)))

        view.simulateAtlasTabSelectionForTesting()
        view.layoutIfNeeded()

        XCTAssertLessThanOrEqual(view.debugPanelFrameForTesting.maxY, view.bounds.maxY)
        XCTAssertTrue(view.isAtlasScrollEnabledForTesting)
    }

    private func makeSnapshot(settings: ImmersiveMapSettings.DebugSettings,
                              atlasPages: [GlobeAtlasDebugPage]) -> DebugOverlayHUDSnapshot {
        DebugOverlayHUDSnapshot(
            coordinateLines: DebugOverlayCoordinateLines(zoom: "z: 1.00", latLon: "lat: 0.000 lon: 0.000"),
            diagnosticsLines: [],
            atlasPages: atlasPages,
            coordinateScale: settings.coordinateScale,
            diagnosticsScale: settings.diagnosticsScale,
            leftPadding: settings.leftPadding,
            topPadding: settings.topPadding,
            sectionSpacing: settings.sectionSpacing,
            textColor: settings.textColor
        )
    }

    private func makeAtlasPage(pageIndex: Int) -> GlobeAtlasDebugPage {
        GlobeAtlasDebugPage(pageIndex: pageIndex,
                            allocations: [
                                GlobeAtlasDebugAllocation(pageIndex: pageIndex,
                                                          slotColumn: 0,
                                                          slotRow: 0,
                                                          slotsPerSide: 4,
                                                          cellSizePx: 1024,
                                                          atlasDepth: .depth2,
                                                          sourceTile: Tile(x: 0, y: 0, z: 2),
                                                          targetTile: Tile(x: 0, y: 0, z: 2),
                                                          screenDemandPx: 512,
                                                          isFallback: false)
                            ])
    }
}

#endif
