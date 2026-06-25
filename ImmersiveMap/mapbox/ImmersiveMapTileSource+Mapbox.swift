// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

extension ImmersiveMapTileSource {
    static func mapbox(tilesetID: String = MapboxTileProvider.defaultTilesetID,
                       accessToken: String?) -> ImmersiveMapTileSource {
        ImmersiveMapTileSource(
            tileBaseURL: URL(string: "https://api.mapbox.com/v4/\(tilesetID)")!,
            accessToken: accessToken,
            authorization: .accessTokenQuery(parameterName: "access_token")
        )
    }
}
