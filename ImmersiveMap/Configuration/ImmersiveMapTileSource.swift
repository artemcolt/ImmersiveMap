// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

public struct ImmersiveMapTileSource: Equatable {
    public typealias AuthorizationMode = ImmersiveMapSettings.TileSettings.NetworkSettings.AuthorizationMode

    public static let defaultMapboxTilesetID = "mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2"

    public var tileBaseURL: URL
    public var accessToken: String?
    public var authorization: AuthorizationMode

    public init(tileBaseURL: URL,
                accessToken: String? = nil,
                authorization: AuthorizationMode = .bearerHeader) {
        self.tileBaseURL = tileBaseURL
        self.accessToken = accessToken
        self.authorization = authorization
    }

    public static func url(_ tileBaseURL: URL) -> ImmersiveMapTileSource {
        ImmersiveMapTileSource(tileBaseURL: tileBaseURL)
    }

    public static func mapbox(tilesetID: String = defaultMapboxTilesetID,
                              accessToken: String?) -> ImmersiveMapTileSource {
        ImmersiveMapTileSource(
            tileBaseURL: URL(string: "https://api.mapbox.com/v4/\(tilesetID)")!,
            accessToken: accessToken,
            authorization: .accessTokenQuery(parameterName: "access_token")
        )
    }

    public func token(_ accessToken: String?) -> ImmersiveMapTileSource {
        var source = self
        source.accessToken = accessToken
        source.authorization = .bearerHeader
        return source
    }

    public func accessToken(_ accessToken: String?,
                            parameterName: String = "access_token") -> ImmersiveMapTileSource {
        var source = self
        source.accessToken = accessToken
        source.authorization = .accessTokenQuery(parameterName: parameterName)
        return source
    }
}
