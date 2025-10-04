//
//  GetMapTileDownloadUrl.swift
//  TucikMap
//
//  Created by Artem on 8/20/25.
//

import Foundation

protocol GetMapTileDownloadUrl {
    func get(tileX: Int, tileY: Int, tileZ: Int) -> URL
}
