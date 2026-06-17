// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import SwiftUI
import ImmersiveMap

@main
struct ImmersiveMapIOSApp: App {
    var body: some Scene {
        WindowGroup {
            HostMapScreen()
        }
    }
}

struct HostMapScreen: View {
    private static let initialCameraPosition = ImmersiveMapCameraPosition(
        latitudeDegrees: 55.7558,
        longitudeDegrees: 37.6173,
        zoom: 0,
        bearing: .pi / 10,
        pitch: .pi / 5
    )

    @State private var camera = ImmersiveMapCameraController()

    var body: some View {
        ImmersiveMapView(
            settings: mapSettings,
            cameraPosition: Self.initialCameraPosition,
            cameraController: camera
        )
        .ignoresSafeArea()
    }

    private var mapSettings: ImmersiveMapSettings {
        var settings = ImmersiveMapSettings.default
        let environment = ProcessInfo.processInfo.environment
        settings.labels.language = .english
        if let mapboxAccessToken = environment["IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN"], mapboxAccessToken.isEmpty == false {
            let tilesetID = Self.resolvedMapboxTilesetID(environment["IMMERSIVE_MAP_MAPBOX_TILESET_ID"])
            settings.tiles.network.tileBaseURL = URL(string: "https://api.mapbox.com/v4/\(tilesetID)")!
            settings.tiles.network.authorizationToken = mapboxAccessToken
            settings.tiles.network.authorizationMode = .accessTokenQuery(parameterName: "access_token")
        } else {
            let tileBaseURLString = environment["IMMERSIVE_MAP_TILE_BASE_URL"] ?? "https://example.com/api/v1/map/tiles"
            settings.tiles.network.tileBaseURL = URL(string: tileBaseURLString)!
            settings.tiles.network.authorizationToken = environment["IMMERSIVE_MAP_AUTH_TOKEN"]
            settings.tiles.network.authorizationMode = .bearerHeader
        }
        if let labelLanguage = environment["IMMERSIVE_MAP_LABEL_LANGUAGE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           labelLanguage.isEmpty == false {
            settings.labels.language = ImmersiveMapSettings.LabelLanguage(labelLanguage)
        }
        if let fallbackPolicy = Self.resolvedLabelFallbackPolicy(environment["IMMERSIVE_MAP_LABEL_FALLBACK_POLICY"]) {
            settings.labels.fallbackPolicy = fallbackPolicy
        }
        settings.renderLoop.forceContinuousRendering = false
        settings.debug.enableDebugPanel = true
        return settings
    }

    private static func resolvedLabelFallbackPolicy(_ configuredPolicy: String?) -> ImmersiveMapSettings.LabelFallbackPolicy? {
        guard let normalized = configuredPolicy?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased(),
            normalized.isEmpty == false else {
            return nil
        }

        switch normalized {
        case "international":
            return .international
        case "localfirst", "local-first", "local":
            return .localFirst
        default:
            return nil
        }
    }

    private static func resolvedMapboxTilesetID(_ configuredTilesetID: String?) -> String {
        let defaultTilesetID = "mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2"
        let legacyDefaultTilesetID = "mapbox.mapbox-streets-v8"
        guard let configuredTilesetID, configuredTilesetID.isEmpty == false else {
            return defaultTilesetID
        }
        return configuredTilesetID == legacyDefaultTilesetID ? defaultTilesetID : configuredTilesetID
    }
}
