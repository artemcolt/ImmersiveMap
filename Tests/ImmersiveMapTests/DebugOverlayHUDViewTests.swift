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

    func testAtlasPreviewDrawsTargetTileLabelInsideAllocation() throws {
        let view = DebugOverlayHUDView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var settings = ImmersiveMapSettings.default.debug
        settings.enableDebugPanel = true
        view.apply(isDebugPanelEnabled: true,
                   controls: DebugOverlayControlSnapshot(axesEnabled: false,
                                                         tileLayersEnabled: false,
                                                         wireframeEnabled: false))
        view.apply(snapshot: makeSnapshot(settings: settings,
                                          atlasPages: [
                                              GlobeAtlasDebugPage(pageIndex: 0,
                                                                  allocations: [
                                                                      GlobeAtlasDebugAllocation(pageIndex: 0,
                                                                                                slotColumn: 1,
                                                                                                slotRow: 2,
                                                                                                slotsPerSide: 4,
                                                                                                cellSizePx: 1024,
                                                                                                atlasDepth: .depth2,
                                                                                                sourceTile: Tile(x: 0, y: 0, z: 2),
                                                                                                targetTile: Tile(x: 2, y: 1, z: 2),
                                                                                                screenDemandPx: 512,
                                                                                                isFallback: false)
                                                                  ])
                                          ]))

        view.simulateAtlasTabSelectionForTesting()
        view.layoutIfNeeded()

        let atlasView = try XCTUnwrap(findAtlasLayoutView(in: view))
        let image = atlasView.renderedImageForTesting(scale: 2)
        let pageSide = min(max(atlasView.bounds.width, 1), 260)
        let cell = pageSide / 4
        let labelProbeRect = CGRect(x: cell + 4,
                                    y: 16 + cell + 4,
                                    width: cell - 8,
                                    height: min(20, cell - 8))

        XCTAssertGreaterThan(image.brightPixelCountForTesting(in: labelProbeRect, scale: 2), 0)
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

    private func findAtlasLayoutView(in view: UIView) -> UIView? {
        if String(describing: type(of: view)) == "DebugOverlayAtlasLayoutView" {
            return view
        }

        for subview in view.subviews {
            if let match = findAtlasLayoutView(in: subview) {
                return match
            }
        }
        return nil
    }
}

private extension UIView {
    func renderedImageForTesting(scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            layer.render(in: context.cgContext)
        }
    }
}

private extension UIImage {
    func brightPixelCountForTesting(in rect: CGRect, scale: CGFloat) -> Int {
        guard let cgImage else { return 0 }

        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let pixelRect = CGRect(x: rect.minX * scale,
                               y: rect.minY * scale,
                               width: rect.width * scale,
                               height: rect.height * scale)
            .integral
            .intersection(imageRect)
        guard pixelRect.isEmpty == false else { return 0 }

        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        return pixels.withUnsafeMutableBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(data: baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return 0
            }

            context.translateBy(x: -pixelRect.minX, y: CGFloat(cgImage.height) - pixelRect.minY)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

            var count = 0
            for offset in stride(from: 0, to: buffer.count, by: bytesPerPixel) {
                let red = buffer[offset]
                let green = buffer[offset + 1]
                let blue = buffer[offset + 2]
                let alpha = buffer[offset + 3]
                if alpha > 180, red > 210, green > 210, blue > 210 {
                    count += 1
                }
            }
            return count
        }
    }
}

#endif
