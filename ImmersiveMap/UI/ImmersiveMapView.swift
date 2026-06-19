// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import SwiftUI
import UIKit // For UIView

public struct ImmersiveMapView: UIViewRepresentable {
    private var settings: ImmersiveMapSettings
    private let cameraPosition: ImmersiveMapCameraPosition?
    private let avatarsController: ImmersiveMapAvatarsController?
    private let cameraController: ImmersiveMapCameraController?
    private let selectionController: ImmersiveMapSelectionController?

    public init(settings: ImmersiveMapSettings = .default,
                avatarsController: ImmersiveMapAvatarsController? = nil,
                cameraPosition: ImmersiveMapCameraPosition? = nil,
                cameraController: ImmersiveMapCameraController? = nil,
                selectionController: ImmersiveMapSelectionController? = nil) {
        self.settings = settings
        self.avatarsController = avatarsController
        self.cameraPosition = cameraPosition
        self.cameraController = cameraController
        self.selectionController = selectionController
    }

    public func makeUIView(context: Context) -> ImmersiveMapUIView {
        let uiView = ImmersiveMapUIView(frame: .zero,
                                        settings: settings,
                                        avatarsController: avatarsController,
                                        cameraPosition: cameraPosition,
                                        cameraController: cameraController,
                                        selectionController: selectionController)
        return uiView
    }

    public func updateUIView(_ uiView: ImmersiveMapUIView, context: Context) {
        uiView.update(settings: settings,
                      avatarsController: avatarsController,
                      cameraController: cameraController,
                      selectionController: selectionController,
                      cameraPosition: cameraPosition)
    }

    public static func dismantleUIView(_ uiView: ImmersiveMapUIView, coordinator: ()) {
        uiView.dismantle()
    }

    public func tileSource(_ source: ImmersiveMapTileSource) -> ImmersiveMapView {
        var view = self
        view.settings = view.settings.tileSource(source)
        return view
    }

    public func tileSource(url: URL,
                           accessToken: String?,
                           authorization: ImmersiveMapSettings.TileSettings.NetworkSettings.AuthorizationMode = .bearerHeader) -> ImmersiveMapView {
        var view = self
        view.settings = view.settings.tileSource(url: url,
                                                 accessToken: accessToken,
                                                 authorization: authorization)
        return view
    }

    public func mapboxTiles(url: URL = URL(string: "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2")!,
                            accessToken: String?) -> ImmersiveMapView {
        var view = self
        view.settings = view.settings.tileSource(ImmersiveMapTileSource(tileBaseURL: url).accessToken(accessToken))
        return view
    }
}

#endif
