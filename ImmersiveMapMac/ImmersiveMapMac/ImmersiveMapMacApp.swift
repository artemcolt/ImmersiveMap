// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import SwiftUI
import ImmersiveMap

@main
struct ImmersiveMapMacApp: App {
    var body: some Scene {
        WindowGroup {
            MapScreen()
        }
    }
}

private struct MapScreen: View {
    @State private var camera = ImmersiveMapCameraController()

    var body: some View {
        ImmersiveMapView()
            .camera(
                camera,
                position: ImmersiveMapCameraPosition(
                    latitudeDegrees: 55.7558,
                    longitudeDegrees: 37.6173,
                    zoom: 0,
                    bearing: .pi / 10,
                    pitch: .pi / 5
                )
            )
            .tileSettings(clearDiskCachesOnLaunch: true)
            .provider(MapboxProvider(accessToken: ProcessInfo.processInfo.environment["IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN"]))
            .debugPanel()
            .earthScene(isEnabled: true)
            .ignoresSafeArea()
            .immersiveMapCameraControls(camera: camera)
    }
}
