// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class OpenStreetMapDefaultMapStyleTests: XCTestCase {
    func testDefaultStyleRendersShortbreadWaterLayers() {
        let style = OpenStreetMapDefaultMapStyle(configuration: .osmDefault,
                                                settings: ImmersiveMapSettings.default.style)

        XCTAssertEqual(makeStyle(style, layerName: "ocean").color,
                       OpenStreetMapDefaultMapStyleConfiguration.osmDefault.layers.water)
        XCTAssertEqual(makeStyle(style, layerName: "water_polygons").color,
                       OpenStreetMapDefaultMapStyleConfiguration.osmDefault.layers.water)
    }

    func testDefaultStyleRendersSyntheticBackgroundAsLand() {
        let style = OpenStreetMapDefaultMapStyle(configuration: .osmDefault,
                                                settings: ImmersiveMapSettings.default.style)
        let background = makeStyle(style, layerName: "background")

        XCTAssertNotEqual(background.key, 0)
        XCTAssertEqual(background.color, OpenStreetMapDefaultMapStyleConfiguration.osmDefault.layers.land)
    }

    func testDefaultStyleRendersShortbreadStreetLines() {
        let style = OpenStreetMapDefaultMapStyle(configuration: .osmDefault,
                                                settings: ImmersiveMapSettings.default.style)
        let street = makeStyle(style,
                               layerName: "streets",
                               properties: ["kind": stringValue("primary")])

        XCTAssertGreaterThan(street.parseGeometryStyleData.lineWidth, 0)
        XCTAssertEqual(street.color, OpenStreetMapDefaultMapStyleConfiguration.osmDefault.layers.roads.major)
    }

    func testDefaultStyleRendersShortbreadBuildings() {
        let style = OpenStreetMapDefaultMapStyle(configuration: .osmDefault,
                                                settings: ImmersiveMapSettings.default.style)
        let building = makeStyle(style, layerName: "buildings")

        XCTAssertEqual(building.color, OpenStreetMapDefaultMapStyleConfiguration.osmDefault.features.buildingFillColor)
    }

    func testDefaultStyleRendersShortbreadPointLabels() {
        let style = OpenStreetMapDefaultMapStyle(configuration: .osmDefault,
                                                settings: ImmersiveMapSettings.default.style)
        let place = makeStyle(style,
                              layerName: "place_labels",
                              properties: ["kind": stringValue("city")])

        XCTAssertNotNil(place.labelTextStyle)
        XCTAssertEqual(place.labelTextStyle?.fillColor,
                       OpenStreetMapDefaultMapStyleConfiguration.osmDefault.labels.place.fillColor)
    }

    func testDefaultLabelSizesAreReadableOnGlobe() {
        let labels = OpenStreetMapDefaultMapStyleConfiguration.osmDefault.labels

        XCTAssertEqual(labels.place.sizePx, 23, accuracy: 0.0001)
        XCTAssertEqual(labels.place.strokeWidthPx, 4.2, accuracy: 0.0001)
        XCTAssertEqual(labels.poi.sizePx, 16, accuracy: 0.0001)
        XCTAssertEqual(labels.poi.strokeWidthPx, 3.6, accuracy: 0.0001)
        XCTAssertEqual(labels.water.sizePx, 18, accuracy: 0.0001)
        XCTAssertEqual(labels.water.strokeWidthPx, 3.1, accuracy: 0.0001)
        XCTAssertEqual(labels.road.sizePx, 15, accuracy: 0.0001)
        XCTAssertEqual(labels.road.strokeWidthPx, 3.0, accuracy: 0.0001)
        XCTAssertEqual(labels.boundary.sizePx, 14, accuracy: 0.0001)
        XCTAssertEqual(labels.boundary.strokeWidthPx, 2.6, accuracy: 0.0001)
    }

    func testCountryLabelsStayReadableThroughZoomThree() throws {
        let style = OpenStreetMapDefaultMapStyle(configuration: .osmDefault,
                                                settings: ImmersiveMapSettings.default.style)
        let lowZoom = try XCTUnwrap(makeStyle(style, layerName: "boundary_labels", zoom: 2).labelTextStyle)
        let zoomThree = try XCTUnwrap(makeStyle(style, layerName: "boundary_labels", zoom: 3).labelTextStyle)
        let nextZoom = try XCTUnwrap(makeStyle(style, layerName: "boundary_labels", zoom: 4).labelTextStyle)

        XCTAssertEqual(lowZoom.sizePx, 28, accuracy: 0.0001)
        XCTAssertEqual(lowZoom.strokeWidthPx, 5.2, accuracy: 0.0001)
        XCTAssertEqual(zoomThree.sizePx, 28, accuracy: 0.0001)
        XCTAssertEqual(zoomThree.strokeWidthPx, 5.2, accuracy: 0.0001)
        XCTAssertEqual(nextZoom.sizePx, 14, accuracy: 0.0001)
        XCTAssertEqual(nextZoom.strokeWidthPx, 2.6, accuracy: 0.0001)
    }

    func testWaterLabelsAreHiddenOnOverviewZooms() {
        let style = OpenStreetMapDefaultMapStyle(configuration: .osmDefault,
                                                settings: ImmersiveMapSettings.default.style)

        XCTAssertNil(makeStyle(style, layerName: "water_polygons_labels", zoom: 5).labelTextStyle)
        XCTAssertNil(makeStyle(style, layerName: "water_lines_labels", zoom: 6).labelTextStyle)
        XCTAssertNotNil(makeStyle(style, layerName: "water_polygons_labels", zoom: 7).labelTextStyle)
        XCTAssertNotNil(makeStyle(style, layerName: "water_lines_labels", zoom: 7).labelTextStyle)
    }

    private func makeStyle(_ style: OpenStreetMapDefaultMapStyle,
                           layerName: String,
                           properties: [String: VectorTile_Tile.Value] = [:],
                           zoom: Int = 12) -> FeatureStyle {
        style.makeStyle(
            data: DetFeatureStyleData(layerName: layerName,
                                      properties: properties,
                                      tile: Tile(x: 0, y: 0, z: zoom))
        )
    }

    private func stringValue(_ value: String) -> VectorTile_Tile.Value {
        var tileValue = VectorTile_Tile.Value()
        tileValue.stringValue = value
        return tileValue
    }
}
