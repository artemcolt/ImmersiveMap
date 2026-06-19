// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class ImmersiveMapTileSourceSettingsTests: XCTestCase {
    #if canImport(UIKit)
    func testImmersiveMapViewModifiersAttachControllersAndInitialCameraPosition() {
        let avatars = ImmersiveMapAvatarsController()
        let camera = ImmersiveMapCameraController()
        let selection = ImmersiveMapSelectionController()
        let cameraPosition = ImmersiveMapCameraPosition(latitudeDegrees: 55.7558,
                                                        longitudeDegrees: 37.6173,
                                                        zoom: 12,
                                                        bearing: .pi / 10,
                                                        pitch: .pi / 5)

        let view = ImmersiveMapView()
            .avatars(avatars)
            .camera(camera, position: cameraPosition)
            .selection(selection)

        let reflectedAvatars: ImmersiveMapAvatarsController? = reflectedObject("avatarsController", in: view)
        let reflectedCamera: ImmersiveMapCameraController? = reflectedObject("cameraController", in: view)
        let reflectedSelection: ImmersiveMapSelectionController? = reflectedObject("selectionController", in: view)

        XCTAssertTrue(reflectedAvatars === avatars)
        XCTAssertTrue(reflectedCamera === camera)
        XCTAssertTrue(reflectedSelection === selection)
        XCTAssertEqual(reflectedValue("cameraPosition", in: view), cameraPosition)
    }
    #endif

    func testDebugPanelEnablesDebugOverlaySettings() {
        let settings = ImmersiveMapSettings.default.debugPanel()

        XCTAssertTrue(settings.debug.enableDebugPanel)
    }

    func testFluentSettingsModifiersReplaceEverySettingsDomain() {
        let renderLoop = ImmersiveMapSettings.RenderLoopSettings(forceContinuousRendering: true,
                                                                 interactionFramesPerSecond: 30,
                                                                 labelFadeFramesPerSecond: 15)
        let camera = ImmersiveMapSettings.CameraSettings(maximumPitch: 1,
                                                         maximumZoom: 17,
                                                         focusedMarkerZoom: 14,
                                                         globeMinimumAbsoluteBearing: 0.5,
                                                         globeBearingUnlockZoom: 4,
                                                         gesturePanTranslationScale: 1,
                                                         worldPanSensitivity: 2,
                                                         worldPanSpeed: 3,
                                                         pinchZoomFactor: 4,
                                                         pinchZoomVelocityFactor: 5,
                                                         pinchZoomVelocityLimit: 6,
                                                         dragZoomFactor: 7,
                                                         dragZoomVelocityFactor: 8,
                                                         dragZoomVelocityLimit: 9,
                                                         rotationGestureSensitivity: 10)
        let presentation = ImmersiveMapSettings.PresentationSettings(automaticTransitionStartZoom: 1,
                                                                     automaticTransitionSpan: 2,
                                                                     globeRadiusScale: 3)
        let tiles = ImmersiveMapSettings.default.tiles
        let labels = ImmersiveMapSettings.default.labels
        let scene = ImmersiveMapSettings.default.scene
        let style = ImmersiveMapSettings.default.style
        let avatars = ImmersiveMapSettings.default.avatars
        let attribution = ImmersiveMapSettings.AttributionSettings(isVisible: false,
                                                                   title: "Tiles",
                                                                   copyright: "Copyright",
                                                                   linkURL: nil)
        let postProcessing = ImmersiveMapSettings.PostProcessingSettings(fxaaEnabled: true)
        let debug = ImmersiveMapSettings.DebugSettings(enableDebugPanel: true,
                                                       coordinateScale: 1,
                                                       diagnosticsScale: 2,
                                                       leftPadding: 3,
                                                       topPadding: 4,
                                                       sectionSpacing: 5,
                                                       textColor: SIMD3<Float>(6, 7, 8))

        let settings = ImmersiveMapSettings.default
            .renderLoopSettings(renderLoop)
            .cameraSettings(camera)
            .presentationSettings(presentation)
            .tileSettings(tiles)
            .labelSettings(labels)
            .sceneSettings(scene)
            .styleSettings(style)
            .avatarSettings(avatars)
            .attributionSettings(attribution)
            .postProcessingSettings(postProcessing)
            .debugSettings(debug)

        XCTAssertEqual(settings.renderLoop, renderLoop)
        XCTAssertEqual(settings.camera, camera)
        XCTAssertEqual(settings.presentation, presentation)
        XCTAssertEqual(settings.tiles, tiles)
        XCTAssertEqual(settings.labels, labels)
        XCTAssertEqual(settings.scene, scene)
        XCTAssertEqual(settings.style, style)
        XCTAssertEqual(settings.avatars, avatars)
        XCTAssertEqual(settings.attribution, attribution)
        XCTAssertEqual(settings.postProcessing, postProcessing)
        XCTAssertEqual(settings.debug, debug)
    }

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

    private func reflectedValue<T>(_ label: String, in value: Any) -> T? {
        Mirror(reflecting: value).children.first { $0.label == label }?.value as? T
    }

    private func reflectedObject<T: AnyObject>(_ label: String, in value: Any) -> T? {
        reflectedValue(label, in: value)
    }
}
