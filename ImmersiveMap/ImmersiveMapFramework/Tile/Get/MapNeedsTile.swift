//
//  GetTile.swift
//  TucikMap
//
//  Created by Artem on 5/30/25.
//

import MetalKit

class MapNeedsTile {
    private var tileDownloader: TileDownloader!
    private var tileDiskCaching: TileDiskCaching!
    private var ongoingTasks: [String: Task<Void, Never>] = [:]
    private let maxConcurrentFetchs: Int
    private let fifo: FIFOStack<Tile>
    private let metalTilesStorage: MetalTilesStorage
    
    init(metalTilesStorage: MetalTilesStorage) {
        self.metalTilesStorage = metalTilesStorage
        self.maxConcurrentFetchs = MapParameters.maxConcurrentFetchs
        let maxFifoCapacity = MapParameters.maxFifoCapacity
        self.fifo = FIFOStack(capacity: maxFifoCapacity)
        
        tileDiskCaching = TileDiskCaching()
        tileDownloader = TileDownloader()
    }
    
    func freePlaces() -> Int {
        return maxConcurrentFetchs - ongoingTasks.count
    }
    
    func request(tiles: [Tile]) {
        if tiles.isEmpty {
            return
        }
        
        // У нас теперь требуются новые тайлы, зачистить очередь
        fifo.clear()
        
        // Запрашиваем столько, сколько можем.
        // Остальное будет добавлено в очередь fifo и вызвано позже
        for tile in tiles {
            requestSingleTile(tile: tile)
        }
    }
    
    private func requestSingleTile(tile: Tile) {
        if ongoingTasks[tile.key()] != nil {
            return
        }
        
        if ongoingTasks.count >= maxConcurrentFetchs {
            fifo.push(tile)
            return
        }
        
        createLoadTileTask(tile: tile)
    }
    
    private func createLoadTileTask(tile: Tile) {
        print("[TILE] " + tile.key() + " load task created.")
        let task = Task {
            // Взять с диска, если нету то пойти в интернет
            await loadTile(tile: tile)
        }
        ongoingTasks[tile.key()] = task
    }
    
    private func loadTile(tile: Tile) async {
        if let data = await tileDiskCaching.requestDiskCached(tile: tile) {
            await parseTile(data: data, tile: tile)
            return
        }
        
        if let data = await tileDownloader.download(tile: tile) {
            tileDiskCaching.saveOnDisk(tile: tile, data: data)
            await parseTile(data: data, tile: tile)
            return
        }
    }
    
    private func parseTile(data: Data?, tile: Tile) async {
        if let data = data {
            await metalTilesStorage.parseTile(tile: tile, data: data)
            print("[TILE] " + tile.key() + " ready.")
        }
        
        await MainActor.run {
            ongoingTasks.removeValue(forKey: tile.key())
            if let deqeueTile = fifo.pop() {
                requestSingleTile(tile: deqeueTile)
            }
        }
    }
}
