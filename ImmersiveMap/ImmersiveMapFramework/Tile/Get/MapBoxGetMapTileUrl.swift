//
//  MapBoxGetMapTileUrl.swift
//  TucikMap
//
//  Created by Artem on 8/20/25.
//

import Foundation

class MapBoxGetMapTileUrl: GetMapTileDownloadUrl {
    private let baseURLString = "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2"
    private let accessToken: String
    
    init(accessToken: String) {
        self.accessToken = accessToken
    }
    
    func get(tileX: Int, tileY: Int, tileZ: Int) -> URL {
        return tileURLFor(zoom: tileZ, x: tileX, y: tileY)
    }
    
    private func tileURLFor(zoom: Int, x: Int, y: Int) -> URL {
        let urlString = "\(baseURLString)/\(zoom)/\(x)/\(y).mvt?access_token=\(accessToken)"
        return URL(string: urlString)!
    }
}
