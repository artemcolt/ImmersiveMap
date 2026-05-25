//
//  DefaultTileLoadPipeline.swift
//  TucikMap
//
//  Created by Artem on 2/18/26.
//

import Foundation

final class DefaultTileLoadPipeline: TileLoadPipeline {
    private let preparedTileDiskCaching: PreparedTileDiskCaching
    private let tileDiskCaching: TileDiskCaching
    private let tileDownloader: TileDownloader
    private weak var tileRenderStore: TileRenderStore?

    init(tileRenderStore: TileRenderStore,
         config: MapSettings,
         preparedTileCacheIdentity: PreparedTileCacheIdentity) {
        self.preparedTileDiskCaching = PreparedTileDiskCaching(config: config,
                                                               cacheIdentity: preparedTileCacheIdentity)
        self.tileDiskCaching = TileDiskCaching(config: config)
        self.tileDownloader = TileDownloader(config: config)
        self.tileRenderStore = tileRenderStore
    }

    func requestPreparedDiskCached(tile: Tile) async -> PreparedTileCPU? {
        await preparedTileDiskCaching.requestPreparedDiskCached(tile: tile)
    }

    func requestDiskCached(tile: Tile) async -> Data? {
        await tileDiskCaching.requestDiskCached(tile: tile)
    }

    func download(tile: Tile) async -> TileDownloader.DownloadResult {
        await tileDownloader.downloadResult(tile: tile)
    }

    func savePreparedOnDisk(tile: Tile, preparedTile: PreparedTileCPU) {
        preparedTileDiskCaching.saveOnDisk(tile: tile, preparedTile: preparedTile)
    }

    func saveOnDisk(tile: Tile, data: Data) {
        tileDiskCaching.saveOnDisk(tile: tile, data: data)
    }

    func removePreparedFromDisk(tile: Tile) {
        preparedTileDiskCaching.removeFromDisk(tile: tile)
    }

    func removeFromDisk(tile: Tile) {
        tileDiskCaching.removeFromDisk(tile: tile)
    }

    func prepare(tile: Tile, data: Data) async -> PreparedTileCPU? {
        guard let tileRenderStore else {
            return nil
        }
        return await tileRenderStore.prepareTile(tile: tile, data: data)
    }

    func materialize(preparedTile: PreparedTileCPU) async -> Bool {
        guard let tileRenderStore else {
            return false
        }
        return await tileRenderStore.materializePreparedTile(preparedTile)
    }

    func parse(tile: Tile, data: Data) async -> Bool {
        guard let preparedTile = await prepare(tile: tile, data: data) else {
            return false
        }
        return await materialize(preparedTile: preparedTile)
    }
}
