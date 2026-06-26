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

    func testImmersiveMapViewCameraControllerAndUIControlsAreSeparateModifiers() {
        let camera = ImmersiveMapCameraController()
        let cameraPosition = ImmersiveMapCameraPosition(latitudeDegrees: 55.7558,
                                                        longitudeDegrees: 37.6173,
                                                        zoom: 12,
                                                        bearing: .pi / 10,
                                                        pitch: .pi / 5)

        let controlledView = ImmersiveMapView()
            .cameraController(camera, position: cameraPosition)
        let controlsView = controlledView
            .enableCameraUIControls()

        let reflectedCamera: ImmersiveMapCameraController? = reflectedObject("cameraController", in: controlledView)
        XCTAssertTrue(reflectedCamera === camera)
        XCTAssertEqual(reflectedValue("cameraPosition", in: controlledView), cameraPosition)
        XCTAssertFalse(String(describing: type(of: controlsView)).isEmpty)
    }
    #endif

    func testDebugPanelEnablesDebugOverlaySettings() {
        let settings = ImmersiveMapSettings.default.debugPanel()

        XCTAssertTrue(settings.debug.enableDebugPanel)
    }

    func testTileProviderAndMapStyleSettingsModifiersStoreMapboxConfiguration() {
        let style = MapboxDefaultMapStyleConfiguration.mapboxDefault.labels { labels in
            labels.district.strokeWidthPx = 1.25
        }

        let tileProvider = MapboxTileProvider(accessToken: "mapbox-token")
        let mapStyle = MapboxMapStyle(configuration: style)
        let settings = ImmersiveMapSettings.default
            .tileProvider(tileProvider)
            .mapStyle(mapStyle)

        XCTAssertEqual(settings.tileProvider, AnyImmersiveMapTileProvider(tileProvider))
        XCTAssertEqual(settings.mapStyle, AnyImmersiveMapMapStyle(mapStyle))
        XCTAssertNotEqual(settings, ImmersiveMapSettings.default)
    }

    #if canImport(UIKit)
    func testTileProviderAndMapStyleViewModifiersStoreMapboxConfiguration() throws {
        let style = MapboxDefaultMapStyleConfiguration.mapboxDefault.labels { labels in
            labels.poi.strokeWidthPx = 3.5
        }
        let tileProvider = MapboxTileProvider(accessToken: "mapbox-token")
        let mapStyle = MapboxMapStyle(configuration: style)

        let view = ImmersiveMapView()
            .tileProvider(tileProvider)
            .mapStyle(mapStyle)

        let settings: ImmersiveMapSettings? = reflectedValue("settings", in: view)
        let unwrappedSettings = try XCTUnwrap(settings)
        XCTAssertEqual(unwrappedSettings.tileProvider, AnyImmersiveMapTileProvider(tileProvider))
        XCTAssertEqual(unwrappedSettings.mapStyle, AnyImmersiveMapMapStyle(mapStyle))
    }
    #endif

    func testEarthSceneModifierControlsFullSunTerminatorAndNightLightsPackage() {
        let settings = ImmersiveMapSettings.default.earthScene(isEnabled: false)

        XCTAssertFalse(settings.scene.earth.isEnabled)
        XCTAssertTrue(settings.scene.earth.sun.isEnabled)
        XCTAssertTrue(settings.scene.earth.nightLights.isEnabled)
    }

    func testTileCacheSettingsModifierUpdatesOnlyProvidedCacheValues() {
        var baseTiles = ImmersiveMapSettings.default.tiles
        baseTiles.network.maxConcurrentFetches = 11
        baseTiles.network.pendingRequestQueueCapacity = 27
        baseTiles.parsing.addTestBorders = true
        baseTiles.cache.clearDiskCachesOnLaunch = false
        baseTiles.cache.rawDiskTimeToLive = 12
        baseTiles.cache.preparedDiskTimeToLive = 34
        baseTiles.cache.memoryCacheSizeInBytes = 56

        let settings = ImmersiveMapSettings.default
            .tileSettings(baseTiles)
            .tileSettings(clearDiskCachesOnLaunch: true,
                          preparedDiskTimeToLive: 78)

        XCTAssertEqual(settings.tiles.network, baseTiles.network)
        XCTAssertEqual(settings.tiles.parsing, baseTiles.parsing)
        XCTAssertEqual(settings.tiles.coverage, baseTiles.coverage)
        XCTAssertTrue(settings.tiles.cache.clearDiskCachesOnLaunch)
        XCTAssertEqual(settings.tiles.cache.rawDiskTimeToLive, 12)
        XCTAssertEqual(settings.tiles.cache.preparedDiskTimeToLive, 78)
        XCTAssertEqual(settings.tiles.cache.memoryCacheSizeInBytes, 56)
    }

    #if canImport(UIKit)
    func testImmersiveMapViewTileCacheSettingsModifierUpdatesOnlyProvidedCacheValues() {
        let view = ImmersiveMapView()
            .tileSettings(clearDiskCachesOnLaunch: true,
                          memoryCacheSizeInBytes: 128)

        let settings: ImmersiveMapSettings? = reflectedValue("settings", in: view)

        XCTAssertTrue(settings?.tiles.cache.clearDiskCachesOnLaunch == true)
        XCTAssertEqual(settings?.tiles.cache.memoryCacheSizeInBytes, 128)
        XCTAssertEqual(settings?.tiles.cache.rawDiskTimeToLive,
                       ImmersiveMapSettings.default.tiles.cache.rawDiskTimeToLive)
        XCTAssertEqual(settings?.tiles.cache.preparedDiskTimeToLive,
                       ImmersiveMapSettings.default.tiles.cache.preparedDiskTimeToLive)
    }
    #endif

    #if canImport(UIKit)
    func testImmersiveMapViewEarthSceneModifierControlsFullSunTerminatorAndNightLightsPackage() {
        let view = ImmersiveMapView().earthScene(isEnabled: false)

        let settings: ImmersiveMapSettings? = reflectedValue("settings", in: view)

        XCTAssertFalse(settings?.scene.earth.isEnabled == true)
        XCTAssertTrue(settings?.scene.earth.sun.isEnabled == true)
        XCTAssertTrue(settings?.scene.earth.nightLights.isEnabled == true)
    }
    #endif

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

    func testVectorTileProviderConfiguresGenericURLAndBearerToken() {
        let url = URL(string: "https://tiles.example.com/vector")!
        let provider = VectorTileProvider(
            id: "custom",
            tileSource: .url(url).token("public-token"),
            maximumTileZoomLevel: 12
        )

        let settings = ImmersiveMapSettings.default.tileProvider(provider)

        XCTAssertEqual(settings.tiles.network.tileBaseURL, url)
        XCTAssertEqual(settings.tiles.network.authorizationToken, "public-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .bearerHeader)
        XCTAssertEqual(settings.tileProvider, AnyImmersiveMapTileProvider(provider))
        XCTAssertEqual(settings.tiles.coverage.maximumZoomLevel, 12)
    }

    func testMapboxTileProviderUsesMapboxVectorTileURLAndAccessTokenQueryAuthorization() {
        let provider = MapboxTileProvider(accessToken: "mapbox-token")

        let settings = ImmersiveMapSettings.default.tileProvider(provider)

        XCTAssertEqual(settings.tiles.network.tileBaseURL.absoluteString,
                       "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2")
        XCTAssertEqual(settings.tiles.network.authorizationToken, "mapbox-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .accessTokenQuery(parameterName: "access_token"))
        XCTAssertEqual(settings.tileProvider, AnyImmersiveMapTileProvider(provider))
    }

    func testVectorTileProviderUpdatesNetworkURLTokenAndAuthorizationMode() {
        let url = URL(string: "https://tiles.example.com/vector")!
        let provider = VectorTileProvider(
            id: "custom-query",
            tileSource: ImmersiveMapTileSource(tileBaseURL: url,
                                               accessToken: "public-token",
                                               authorization: .accessTokenQuery(parameterName: "access_token"))
        )

        let settings = ImmersiveMapSettings.default.tileProvider(provider)

        XCTAssertEqual(settings.tiles.network.tileBaseURL, url)
        XCTAssertEqual(settings.tiles.network.authorizationToken, "public-token")
        XCTAssertEqual(settings.tiles.network.authorizationMode, .accessTokenQuery(parameterName: "access_token"))
    }

    func testMapboxTileProviderTilesetIDControlsMapboxVectorTileURL() {
        let settings = ImmersiveMapSettings.default.tileProvider(
            MapboxTileProvider(accessToken: "mapbox-token", tilesetID: "example.tileset")
        )

        XCTAssertEqual(settings.tiles.network.tileBaseURL.absoluteString,
                       "https://api.mapbox.com/v4/example.tileset")
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
