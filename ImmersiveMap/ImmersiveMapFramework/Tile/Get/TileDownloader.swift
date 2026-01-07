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
    private let accessToken: String?
    private let session: URLSession
    private let debugAssemblingMap: Bool

    init(config: MapConfiguration) {
        configuration = URLSessionConfiguration.default
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv12
        accessToken = ProcessInfo.processInfo.environment["MAPBOX"]
        self.mapTileDownloader = MapBoxGetMapTileUrl(accessToken: accessToken ?? "")
        self.session = URLSession(configuration: configuration)
        self.debugAssemblingMap = config.debugAssemblingMap
    }
    
    func download(tile: Tile) async -> Data? {
        if accessToken == nil {
            return nil
        }
        let zoom = tile.z
        let x = tile.x
        let y = tile.y
        
        if debugAssemblingMap { print("Download tile \(tile)") }
        
        // Create new download task
        let tileURL = mapTileDownloader.get(tileX: x, tileY: y, tileZ: zoom)
        if let response = try? await session.data(from: tileURL) {
            if debugAssemblingMap { print("Tile is downloaded \(tile)") }
            return response.0
        }
        
        if debugAssemblingMap { print("Downloading tile failed \(tile)") }
        return nil
    }
}
