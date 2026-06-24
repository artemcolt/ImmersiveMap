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
}
