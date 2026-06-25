// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

public struct OpenStreetMapProvider: ImmersiveMapProvider {
    public static let shortbreadV1TileBaseURL = URL(string: "https://vector.openstreetmap.org/shortbread_v1")!
    public static let shortbreadV1MaximumTileZoomLevel = 14

    public let tileBaseURL: URL

    private let styleMode: StyleMode

    public var id: String {
        "openstreetmap"
    }

    public var cacheNamespace: String {
        "openstreetmap-shortbread-v1"
    }

    public var configurationFingerprint: UInt64 {
        var hash: UInt64 = 1469598103934665603
        mix(id, into: &hash)
        mix(cacheNamespace, into: &hash)
        mix(tileBaseURL.absoluteString, into: &hash)
        mix(String(styleMode.cacheFingerprint), into: &hash)
        return hash
    }

    public var tileSource: ImmersiveMapTileSource {
        ImmersiveMapTileSource(tileBaseURL: tileBaseURL)
    }

    public var vectorTileStyle: any ImmersiveMapVectorTileStyle {
        styleMode.vectorTileStyle
    }

    public init(tileBaseURL: URL = OpenStreetMapProvider.shortbreadV1TileBaseURL,
                style: OpenStreetMapDefaultMapStyleConfiguration = .osmDefault) {
        self.tileBaseURL = tileBaseURL
        self.styleMode = .shortbreadDefault(style)
    }

    public init(tileBaseURL: URL = OpenStreetMapProvider.shortbreadV1TileBaseURL,
                customStyle: any ImmersiveMapVectorTileStyle) {
        self.tileBaseURL = tileBaseURL
        self.styleMode = .custom(customStyle)
    }

    private func mix(_ string: String, into hash: inout UInt64) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
    }
}

extension OpenStreetMapProvider: ImmersiveMapProviderTileCoverageConfiguring {
    public var maximumTileZoomLevel: Int? {
        Self.shortbreadV1MaximumTileZoomLevel
    }
}

extension OpenStreetMapProvider: ImmersiveMapProviderRuntime {
    func makeRuntimeMapStyle(settings: ImmersiveMapSettings.StyleSettings) -> any ImmersiveMapStyle {
        switch styleMode {
        case .shortbreadDefault(let configuration):
            return OpenStreetMapDefaultMapStyle(configuration: configuration, settings: settings)
        case .custom(let style):
            return GenericVectorTileStyle(providerID: id, style: style, settings: settings)
        }
    }

    func makeLabelProviderProfile(settings: ImmersiveMapSettings) -> any VectorTileLabelProviderProfile {
        OpenStreetMapVectorTileLabelProviderProfile(settings: settings)
    }
}

private enum StyleMode {
    case shortbreadDefault(OpenStreetMapDefaultMapStyleConfiguration)
    case custom(any ImmersiveMapVectorTileStyle)

    var cacheFingerprint: UInt32 {
        switch self {
        case .shortbreadDefault(let configuration):
            return configuration.cacheFingerprint
        case .custom(let style):
            return style.cacheFingerprint
        }
    }

    var vectorTileStyle: any ImmersiveMapVectorTileStyle {
        switch self {
        case .shortbreadDefault(let configuration):
            return OpenStreetMapProviderVectorTileStyle(configuration: configuration)
        case .custom(let style):
            return style
        }
    }
}

private struct OpenStreetMapProviderVectorTileStyle: ImmersiveMapVectorTileStyle {
    let configuration: OpenStreetMapDefaultMapStyleConfiguration

    var cacheFingerprint: UInt32 {
        configuration.cacheFingerprint
    }

    func makeStyle(for feature: ImmersiveMapFeatureStyleContext) -> ImmersiveMapFeatureStyle {
        .hidden
    }
}
