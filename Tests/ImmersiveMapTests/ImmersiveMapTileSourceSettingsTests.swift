// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class ImmersiveMapTileSourceSettingsTests: XCTestCase {
    func testTileSourceValueConfiguresGenericURLAndBearerToken() {
        let url = URL(string: "https://tiles.example.com/vector")!
        let source = ImmersiveMapTileSource.url(url).token("public-token")

        let settings = ImmersiveMapSettings.default.tileSource(source)

        XCTAssertEqual(settings.tiles.network.tileBaseURL, url)
        XCTAssertEqual(settings.tiles.network.authorizationToken, "public-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .bearerHeader)
    }

    func testMapboxTileSourceUsesMapboxVectorTileURLAndAccessTokenQueryAuthorization() {
        let source = ImmersiveMapTileSource.mapbox(accessToken: "mapbox-token")

        let settings = ImmersiveMapSettings.default.tileSource(source)

        XCTAssertEqual(settings.tiles.network.tileBaseURL.absoluteString,
                       "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2")
        XCTAssertEqual(settings.tiles.network.authorizationToken, "mapbox-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .accessTokenQuery(parameterName: "access_token"))
    }

    func testTileSourceUpdatesNetworkURLTokenAndAuthorizationMode() {
        let url = URL(string: "https://tiles.example.com/vector")!

        let settings = ImmersiveMapSettings.default.tileSource(
            url: url,
            accessToken: "public-token",
            authorization: .accessTokenQuery(parameterName: "access_token")
        )

        XCTAssertEqual(settings.tiles.network.tileBaseURL, url)
        XCTAssertEqual(settings.tiles.network.authorizationToken, "public-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .accessTokenQuery(parameterName: "access_token"))
    }

    func testMapboxTilesUsesMapboxVectorTileURLAndAccessTokenQueryAuthorization() {
        let settings = ImmersiveMapSettings.default.mapboxTiles(accessToken: "mapbox-token")

        XCTAssertEqual(settings.tiles.network.tileBaseURL.absoluteString,
                       "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2")
        XCTAssertEqual(settings.tiles.network.authorizationToken, "mapbox-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .accessTokenQuery(parameterName: "access_token"))
    }
}
