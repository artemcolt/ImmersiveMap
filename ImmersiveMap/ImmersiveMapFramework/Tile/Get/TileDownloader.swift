//
//  TileDownloader.swift
//  TucikMap
//
//  Created by Artem on 5/28/25.
//

import Foundation

class TileDownloader {
    private let configuration: URLSessionConfiguration
    private let mapTileDownloader: GetMapTileDownloadUrl

    init() {
        configuration = URLSessionConfiguration.default
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv12
        let accessToken = ProcessInfo.processInfo.environment["MAPBOX"]! as String
        self.mapTileDownloader = MapBoxGetMapTileUrl(accessToken: accessToken)
    }
    
    func download(tile: Tile) async -> Data? {
        let zoom = tile.z
        let x = tile.x
        let y = tile.y
        let debugAssemblingMap = MapParameters.debugAssemblingMap
        
        if debugAssemblingMap { print("Download tile \(tile)") }
        
        // Create new download task
        let tileURL = mapTileDownloader.get(tileX: x, tileY: y, tileZ: zoom)
        let session: URLSession = URLSession(configuration: configuration)
        if let response = try? await session.data(from: tileURL) {
            if debugAssemblingMap { print("Tile is downloaded \(tile)") }
            return response.0
        }
        
        if debugAssemblingMap { print("Downloading tile failed \(tile)") }
        return nil
    }
}
