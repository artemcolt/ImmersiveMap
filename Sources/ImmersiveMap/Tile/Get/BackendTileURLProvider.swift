//
//  BackendTileURLProvider.swift
//  TucikMap
//
//  Created by Artem on 8/20/25.
//

import Foundation

class BackendTileURLProvider: GetMapTileDownloadUrl {
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func get(tileX: Int, tileY: Int, tileZ: Int) -> URL {
        return tileURLFor(zoom: tileZ, x: tileX, y: tileY)
    }

    private func tileURLFor(zoom: Int, x: Int, y: Int) -> URL {
        baseURL
            .appendingPathComponent("\(zoom)")
            .appendingPathComponent("\(x)")
            .appendingPathComponent("\(y).mvt")
    }
}
