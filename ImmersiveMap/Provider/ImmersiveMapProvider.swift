// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

public protocol ImmersiveMapProvider {
    var id: String { get }
    var cacheNamespace: String { get }
    var configurationFingerprint: UInt64 { get }
    var tileSource: ImmersiveMapTileSource { get }
    var vectorTileStyle: any ImmersiveMapVectorTileStyle { get }
}

protocol ImmersiveMapProviderRuntime {
    func makeRuntimeMapStyle(settings: ImmersiveMapSettings.StyleSettings) -> any ImmersiveMapStyle
    func makeLabelProviderProfile(settings: ImmersiveMapSettings) -> any VectorTileLabelProviderProfile
}

public struct AnyImmersiveMapProvider: Equatable {
    public let id: String
    public let cacheNamespace: String
    public let configurationFingerprint: UInt64
    public let tileSource: ImmersiveMapTileSource

    let vectorTileStyle: any ImmersiveMapVectorTileStyle
    private let runtimeMapStyleFactory: (ImmersiveMapSettings.StyleSettings) -> any ImmersiveMapStyle
    private let labelProviderProfileFactory: (ImmersiveMapSettings) -> any VectorTileLabelProviderProfile

    public init<P: ImmersiveMapProvider>(_ provider: P) {
        self.id = provider.id
        self.cacheNamespace = provider.cacheNamespace
        self.configurationFingerprint = provider.configurationFingerprint
        self.tileSource = provider.tileSource
        self.vectorTileStyle = provider.vectorTileStyle

        if let runtimeProvider = provider as? ImmersiveMapProviderRuntime {
            self.runtimeMapStyleFactory = runtimeProvider.makeRuntimeMapStyle
            self.labelProviderProfileFactory = runtimeProvider.makeLabelProviderProfile
        } else {
            self.runtimeMapStyleFactory = { settings in
                GenericVectorTileStyle(providerID: provider.id,
                                       style: provider.vectorTileStyle,
                                       settings: settings)
            }
            self.labelProviderProfileFactory = { settings in
                GenericVectorTileLabelProviderProfile(providerID: provider.id,
                                                      settings: settings)
            }
        }
    }

    public static func == (lhs: AnyImmersiveMapProvider, rhs: AnyImmersiveMapProvider) -> Bool {
        lhs.id == rhs.id
            && lhs.cacheNamespace == rhs.cacheNamespace
            && lhs.configurationFingerprint == rhs.configurationFingerprint
            && lhs.tileSource == rhs.tileSource
    }

    func makeRuntimeMapStyle(settings: ImmersiveMapSettings.StyleSettings) -> any ImmersiveMapStyle {
        runtimeMapStyleFactory(settings)
    }

    func makeLabelProviderProfile(settings: ImmersiveMapSettings) -> any VectorTileLabelProviderProfile {
        labelProviderProfileFactory(settings)
    }
}

public struct CustomVectorTileProvider: ImmersiveMapProvider {
    public let id: String
    public let cacheNamespace: String
    public let configurationFingerprint: UInt64
    public let tileSource: ImmersiveMapTileSource
    public let vectorTileStyle: any ImmersiveMapVectorTileStyle

    public init(id: String,
                cacheNamespace: String? = nil,
                tileSource: ImmersiveMapTileSource,
                style: any ImmersiveMapVectorTileStyle,
                configurationFingerprint: UInt64? = nil) {
        self.id = id
        self.cacheNamespace = cacheNamespace ?? id
        self.tileSource = tileSource
        self.vectorTileStyle = style
        self.configurationFingerprint = configurationFingerprint
            ?? Self.makeFingerprint(id: id,
                                    cacheNamespace: cacheNamespace ?? id,
                                    tileSource: tileSource,
                                    styleFingerprint: style.cacheFingerprint)
    }

    private static func makeFingerprint(id: String,
                                        cacheNamespace: String,
                                        tileSource: ImmersiveMapTileSource,
                                        styleFingerprint: UInt32) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        mix(id, into: &hash)
        mix(cacheNamespace, into: &hash)
        mix(tileSource.tileBaseURL.absoluteString, into: &hash)
        mix(String(styleFingerprint), into: &hash)
        return hash
    }

    private static func mix(_ string: String, into hash: inout UInt64) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
    }
}
