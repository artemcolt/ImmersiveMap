//
//  GetTile.swift
//  TucikMap
//
//  Created by Artem on 5/30/25.
//

import Foundation
import MetalKit

class MapNeedsTile {
    private var tileDownloader: TileDownloader!
    private var tileDiskCaching: TileDiskCaching!
    private var ongoingTasks: [Tile: Task<Void, Never>] = [:]
    private let maxConcurrentFetchs: Int
    private let fifo: FIFOStack<Tile>
    private let metalTilesStorage: MetalTilesStorage
    private let config: MapConfiguration
    private let stateQueue = DispatchQueue(label: "ImmersiveMap.MapNeedsTile.state")
    
    init(metalTilesStorage: MetalTilesStorage, config: MapConfiguration) {
        self.metalTilesStorage = metalTilesStorage
        self.config = config
        self.maxConcurrentFetchs = config.maxConcurrentFetchs
        let maxFifoCapacity = config.maxFifoCapacity
        self.fifo = FIFOStack(capacity: maxFifoCapacity)
        
        tileDiskCaching = TileDiskCaching(config: config)
        tileDownloader = TileDownloader(config: config)
    }
    
    func freePlaces() -> Int {
        return stateQueue.sync {
            maxConcurrentFetchs - ongoingTasks.count
        }
    }
    
    func request(tiles: [Tile]) {
        if tiles.isEmpty {
            return
        }
        
        // У нас теперь требуются новые тайлы, зачистить очередь
        stateQueue.sync {
            fifo.clear()
        }
        
        // Запрашиваем столько, сколько можем.
        // Остальное будет добавлено в очередь fifo и вызвано позже
        for tile in tiles {
            requestSingleTile(tile: tile)
        }
    }
    
    private func requestSingleTile(tile: Tile) {
        stateQueue.sync {
            if ongoingTasks[tile] != nil {
                return
            }
            
            if ongoingTasks.count >= maxConcurrentFetchs {
                fifo.push(tile)
                return
            }
            
            createLoadTileTask(tile: tile)
        }
    }
    
    private func createLoadTileTask(tile: Tile) {
        print("[TILE] \(tile) load task created.")
        let task = Task {
            // Взять с диска, если нету то пойти в интернет
            await loadTile(tile: tile)
        }
        ongoingTasks[tile] = task
    }
    
    private func loadTile(tile: Tile) async {
        defer {
            Task { @MainActor in
                finishLoading(tile: tile)
            }
        }
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
            print("[TILE] \(tile) ready.")
        }
    }

    @MainActor
    private func finishLoading(tile: Tile) {
        var nextTile: Tile?
        stateQueue.sync {
            ongoingTasks.removeValue(forKey: tile)
            nextTile = fifo.pop()
        }
        if let deqeueTile = nextTile {
            requestSingleTile(tile: deqeueTile)
        }
    }
}
