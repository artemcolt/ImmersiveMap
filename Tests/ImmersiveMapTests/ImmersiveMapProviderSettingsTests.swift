// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class ImmersiveMapProviderSettingsTests: XCTestCase {
    func testMapboxProviderConfiguresNetworkSourceAndStyleInOneModifier() {
        let style = MapboxDefaultMapStyleConfiguration.mapboxDefault.labels { labels in
            labels.district.strokeWidthPx = 1.25
        }

        let settings = ImmersiveMapSettings.default.provider(
            MapboxProvider(accessToken: "mapbox-token", style: style)
        )

        XCTAssertEqual(settings.provider.id, "mapbox")
        XCTAssertEqual(settings.provider.cacheNamespace, "mapbox")
        XCTAssertEqual(settings.tiles.network.tileBaseURL.absoluteString,
                       "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2")
        XCTAssertEqual(settings.tiles.network.authorizationToken, "mapbox-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .accessTokenQuery(parameterName: "access_token"))
        XCTAssertEqual(settings.provider.configurationFingerprint,
                       AnyImmersiveMapProvider(MapboxProvider(accessToken: "mapbox-token",
                                                             style: style)).configurationFingerprint)
        XCTAssertEqual(settings.tiles.coverage.maximumZoomLevel, 20)
    }

    func testMapboxProviderRestoresDefaultMaximumZoomAfterOpenStreetMapProvider() {
        let settings = ImmersiveMapSettings.default
            .provider(OpenStreetMapProvider())
            .provider(MapboxProvider(accessToken: nil))

        XCTAssertEqual(settings.tiles.coverage.maximumZoomLevel, 20)
    }

    func testProviderStyleChangeRebuildsPreparedData() {
        let oldSettings = ImmersiveMapSettings.default.provider(
            MapboxProvider(accessToken: "mapbox-token", style: .mapboxDefault)
        )
        let newSettings = ImmersiveMapSettings.default.provider(
            MapboxProvider(accessToken: "mapbox-token",
                           style: .mapboxDefault.layers { layers in
                               layers.water = SIMD4<Float>(0.12, 0.34, 0.56, 1.0)
                           })
        )

        let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: oldSettings, to: newSettings)

        XCTAssertEqual(plan.changedDomains, [.style])
        XCTAssertEqual(plan.actions, [.invalidateCaches, .rebuildPreparedData, .rebuildGPUResources, .recreateRenderer])
        XCTAssertTrue(plan.requiresRendererRecreation)
    }

    func testCustomProviderCanConfigureMaximumTileZoomLevel() {
        let settings = ImmersiveMapSettings.default.provider(
            CustomVectorTileProvider(
                id: "example",
                tileSource: .url(URL(string: "https://example.com/api/v1/map/tiles")!),
                style: BasicVectorTileStyle(),
                maximumTileZoomLevel: 12
            )
        )

        XCTAssertEqual(settings.tiles.coverage.maximumZoomLevel, 12)
    }

    func testOpenStreetMapProviderConfiguresShortbreadVectorTileEndpoint() {
        let settings = ImmersiveMapSettings.default.provider(OpenStreetMapProvider())

        XCTAssertEqual(settings.provider.id, "openstreetmap")
        XCTAssertEqual(settings.provider.cacheNamespace, "openstreetmap-shortbread-v1")
        XCTAssertEqual(settings.tiles.network.tileBaseURL.absoluteString,
                       "https://vector.openstreetmap.org/shortbread_v1")
        XCTAssertNil(settings.tiles.network.authorizationToken)
        XCTAssertEqual(settings.tiles.network.authorizationMode, .bearerHeader)
        XCTAssertEqual(settings.tiles.coverage.maximumZoomLevel, 14)
    }

    func testOpenStreetMapProviderStyleChangeRebuildsPreparedData() {
        let oldSettings = ImmersiveMapSettings.default.provider(
            OpenStreetMapProvider(style: .osmDefault)
        )
        let newSettings = ImmersiveMapSettings.default.provider(
            OpenStreetMapProvider(style: .osmDefault.layers { layers in
                layers.water = SIMD4<Float>(0.18, 0.38, 0.65, 1.0)
            })
        )

        let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: oldSettings, to: newSettings)

        XCTAssertEqual(plan.changedDomains, [.style])
        XCTAssertEqual(plan.actions, [.invalidateCaches, .rebuildPreparedData, .rebuildGPUResources, .recreateRenderer])
        XCTAssertTrue(plan.requiresRendererRecreation)
    }
}
