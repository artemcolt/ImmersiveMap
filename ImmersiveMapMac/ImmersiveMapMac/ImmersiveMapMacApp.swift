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
    private let tileProvider = ExampleMapProvider.makeTileProvider()
    private let mapStyle = ExampleMapProvider.makeMapStyle()

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
            .tileProvider(tileProvider)
            .mapStyle(mapStyle)
            .debugPanel()
            .earthScene(isEnabled: true)
            .ignoresSafeArea()
            .immersiveMapCameraControls(camera: camera)
    }
}
