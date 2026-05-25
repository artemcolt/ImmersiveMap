//
//  TileLoadPipeline.swift
//  TucikMap
//
//  Created by Artem on 2/18/26.
//

import Foundation

protocol TileLoadPipeline {
    func requestPreparedDiskCached(tile: Tile) async -> PreparedTileCPU?
    func requestDiskCached(tile: Tile) async -> Data?
    func download(tile: Tile) async -> TileDownloader.DownloadResult
    func savePreparedOnDisk(tile: Tile, preparedTile: PreparedTileCPU)
    func saveOnDisk(tile: Tile, data: Data)
    func removePreparedFromDisk(tile: Tile)
    func removeFromDisk(tile: Tile)
    func prepare(tile: Tile, data: Data) async -> PreparedTileCPU?
    func materialize(preparedTile: PreparedTileCPU) async -> Bool
    func parse(tile: Tile, data: Data) async -> Bool
}
