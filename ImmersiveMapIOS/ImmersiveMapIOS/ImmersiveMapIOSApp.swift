// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import SwiftUI
import UIKit
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
    @State private var avatars = ImmersiveMapAvatarsController()

    var body: some View {
        ImmersiveMapView(
            settings: mapSettings,
            avatarsController: avatars,
            cameraPosition: Self.initialCameraPosition,
            cameraController: camera
        )
        .ignoresSafeArea()
        .task {
            await seedPreviewMarkers()
        }
    }

    private var mapSettings: ImmersiveMapSettings {
        var settings = ImmersiveMapSettings.default
        let environment = ProcessInfo.processInfo.environment
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
        settings.renderLoop.forceContinuousRendering = false
        settings.debug.enableDebugPanel = true
        return settings
    }

    private static func resolvedMapboxTilesetID(_ configuredTilesetID: String?) -> String {
        let defaultTilesetID = "mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2"
        let legacyDefaultTilesetID = "mapbox.mapbox-streets-v8"
        guard let configuredTilesetID, configuredTilesetID.isEmpty == false else {
            return defaultTilesetID
        }
        return configuredTilesetID == legacyDefaultTilesetID ? defaultTilesetID : configuredTilesetID
    }

    @MainActor
    private func seedPreviewMarkers() async {
        avatars.set([
            AvatarMarker(
                id: 1,
                coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
                image: Self.markerImage(fill: UIColor(red: 0.16, green: 0.64, blue: 0.98, alpha: 1)),
                batteryBadge: AvatarBatteryBadge(levelPct: 82),
                speedBadge: AvatarSpeedBadge(kilometersPerHour: 5),
                isSelected: true
            ),
            AvatarMarker(
                id: 2,
                coordinate: GeoCoordinate(latitude: 55.7512, longitude: 37.6297),
                image: Self.markerImage(fill: UIColor(red: 0.96, green: 0.35, blue: 0.31, alpha: 1)),
                batteryBadge: AvatarBatteryBadge(levelPct: 54),
                speedBadge: AvatarSpeedBadge(kilometersPerHour: 18)
            )
        ])
    }

    private static func markerImage(fill: UIColor) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
            fill.setFill()
            context.cgContext.fillEllipse(in: rect)
            UIColor.white.withAlphaComponent(0.92).setStroke()
            context.cgContext.setLineWidth(8)
            context.cgContext.strokeEllipse(in: rect)
        }
    }
}
