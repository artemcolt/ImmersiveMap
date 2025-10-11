//
//  MetalTilesStorage.swift
//  TucikMap
//
//  Created by Artem on 6/6/25.
//

import Foundation
internal import GISTools
import MetalKit

class MetalTilesStorage {
    var mapNeedsTile                : MapNeedsTile!
    var tileParser                  : TileMvtParser!
    private var memoryMetalTile     : MemoryMetalTileCache!
    private var onMetalingTileEnd   : [(Tile) -> Void] = []
    private let metalDevice         : MTLDevice
    
    init(
        mapStyle: MapStyle,
        metalDevice: MTLDevice,
    ) {
        self.metalDevice = metalDevice
        let maxCachedTilesMemory = MapParameters.maxCachedTilesMemInBytes
        memoryMetalTile = MemoryMetalTileCache(maxCacheSizeInBytes: maxCachedTilesMemory)
        let determineFeatureStyle = DetermineFeatureStyle(mapStyle: mapStyle)
        tileParser = TileMvtParser(determineFeatureStyle: determineFeatureStyle)
        mapNeedsTile = MapNeedsTile(onComplete: onTileComplete)
    }
    
    func addHandler(handler: @escaping (Tile) -> Void) {
        onMetalingTileEnd.append(handler)
    }
    
    private func onTileComplete(data: Data?, tile: Tile) {
        guard let data = data else { return }
        
        let debugAssemblingMap = MapParameters.debugAssemblingMap
        let tileExtent = 4096
        if debugAssemblingMap { print("Parsing and metaling \(tile)") }
        Task {
            let parsedTile = tileParser.parse(
                tile: tile,
                mvtData: data
            )
            
            let tileBuffers = TileBuffers(
                verticesBuffer: metalDevice.makeBuffer(
                    bytes: parsedTile.drawingPolygon.vertices,
                    length: parsedTile.drawingPolygon.vertices.count * MemoryLayout<TilePipeline.VertexIn>.stride
                )!,
                indicesBuffer: metalDevice.makeBuffer(
                    bytes: parsedTile.drawingPolygon.indices,
                    length: parsedTile.drawingPolygon.indices.count * MemoryLayout<UInt32>.stride
                )!,
                stylesBuffer: metalDevice.makeBuffer(
                    bytes: parsedTile.styles,
                    length: parsedTile.styles.count * MemoryLayout<TilePolygonStyle>.stride
                )!,
                indicesCount: parsedTile.drawingPolygon.indices.count,
                verticesCount: parsedTile.drawingPolygon.vertices.count
            )
            
            
            let metalTile = MetalTile(tile: tile, tileBuffers: tileBuffers)
            
            await MainActor.run {
                let key = tile.key()
                self.memoryMetalTile.setTileData(
                    tile: metalTile,
                    forKey: key
                )
                if onMetalingTileEnd.count > 2 {
                    print("Warning. onMetalingTileEnd has ", onMetalingTileEnd.count, " handlers.")
                }
                for handler in onMetalingTileEnd {
                    handler(tile)
                }
            }
        }
    }
    
    func getMetalTile(tile: Tile) -> MetalTile? {
        return memoryMetalTile.getTile(forKey: tile.key())
    }
    
    func requestMetalTile(tile: Tile) {
        mapNeedsTile.please(tile: tile)
    }
}
