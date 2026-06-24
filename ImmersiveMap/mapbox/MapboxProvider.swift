// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

public struct MapboxProvider: ImmersiveMapProvider {
    public static let defaultTilesetID = "mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2"

    public let accessToken: String?
    public let tilesetID: String
    public let style: MapboxDefaultMapStyleConfiguration

    public var id: String {
        "mapbox"
    }

    public var cacheNamespace: String {
        "mapbox"
    }

    public var configurationFingerprint: UInt64 {
        var hash: UInt64 = 1469598103934665603
        mix(id, into: &hash)
        mix(tilesetID, into: &hash)
        mix(String(style.cacheFingerprint), into: &hash)
        return hash
    }

    public var tileSource: ImmersiveMapTileSource {
        .mapbox(tilesetID: tilesetID, accessToken: accessToken)
    }

    public var vectorTileStyle: any ImmersiveMapVectorTileStyle {
        MapboxProviderVectorTileStyle(configuration: style)
    }

    public init(accessToken: String?,
                tilesetID: String = MapboxProvider.defaultTilesetID,
                style: MapboxDefaultMapStyleConfiguration = .mapboxDefault) {
        self.accessToken = accessToken
        self.tilesetID = tilesetID
        self.style = style
    }

    private func mix(_ string: String, into hash: inout UInt64) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
    }
}

extension MapboxProvider: ImmersiveMapProviderRuntime {
    func makeRuntimeMapStyle(settings: ImmersiveMapSettings.StyleSettings) -> any ImmersiveMapStyle {
        MapboxDefaultMapStyle(configuration: style, settings: settings)
    }

    func makeLabelProviderProfile(settings: ImmersiveMapSettings) -> any VectorTileLabelProviderProfile {
        MapboxVectorTileLabelProviderProfile(settings: settings)
    }
}

private struct MapboxProviderVectorTileStyle: ImmersiveMapVectorTileStyle {
    let configuration: MapboxDefaultMapStyleConfiguration

    var cacheFingerprint: UInt32 {
        configuration.cacheFingerprint
    }

    func makeStyle(for feature: ImmersiveMapFeatureStyleContext) -> ImmersiveMapFeatureStyle {
        .hidden
    }
}
