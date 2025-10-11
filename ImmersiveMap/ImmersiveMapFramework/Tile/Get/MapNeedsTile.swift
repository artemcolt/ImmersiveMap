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
    private var onComplete: (Data?, Tile) -> Void
    private var ongoingTasks: [String: Task<Void, Never>] = [:]
    private let maxConcurrentFetchs: Int
    private let lifo: LIFOStack<Tile>
    
    init(onComplete: @escaping (Data?, Tile) -> Void) {
        self.onComplete = onComplete
        self.maxConcurrentFetchs = MapParameters.maxConcurrentFetchs
        let maxFifoCapacity = MapParameters.maxFifoCapacity
        self.lifo = LIFOStack(capacity: maxFifoCapacity)
        
        tileDiskCaching = TileDiskCaching()
        tileDownloader = TileDownloader()
    }
    
    func freePlaces() -> Int {
        return maxConcurrentFetchs - ongoingTasks.count
    }
    
    func please(tile: Tile) {
        let debugAssemblingMap = MapParameters.debugAssemblingMap
        
        if ongoingTasks[tile.key()] != nil {
            if debugAssemblingMap { print("Requested already tile \(tile)") }
            return
        }
        
        if ongoingTasks.count >= maxConcurrentFetchs {
            lifo.push(tile)
            if debugAssemblingMap { print("Request fifo enque tile \(tile)") }
            return
        }
        
        if debugAssemblingMap { print("Request tile \(tile)") }
        let task = Task {
            if let data = await tileDiskCaching.requestDiskCached(tile: tile) {
                if debugAssemblingMap {print("Fetched disk tile: \(tile.key())")}
                await MainActor.run {
                    _onComplete(data: data, tile: tile)
                }
                return
            }
            
            if let data = await tileDownloader.download(tile: tile) {
                tileDiskCaching.saveOnDisk(tile: tile, data: data)
                await MainActor.run {
                    _onComplete(data: data, tile: tile)
                }
                return
            }
        }
        
        ongoingTasks[tile.key()] = task
    }
    
    private func _onComplete(data: Data?, tile: Tile) {
        ongoingTasks.removeValue(forKey: tile.key())
        if let deqeueTile = lifo.pop() {
            please(tile: deqeueTile)
        }
        onComplete(data, tile)
    }
}
