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
    private var mapNeedsTile        : MapNeedsTile?
    var tileParser                  : TileMvtParser!
    private var memoryMetalTile     : MemoryMetalTileCache!
    private let metalDevice         : MTLDevice
    private let debugAssemblingMap  = MapParameters.debugAssemblingMap
    private let renderer            : Renderer
    private let textRenderer        : TextRenderer
    
    init(
        mapStyle: MapStyle,
        metalDevice: MTLDevice,
        renderer: Renderer,
        textRenderer: TextRenderer
    ) {
        self.metalDevice = metalDevice
        self.renderer = renderer
        self.textRenderer = textRenderer
        let maxCachedTilesMemory = MapParameters.maxCachedTilesMemInBytes
        memoryMetalTile = MemoryMetalTileCache(maxCacheSizeInBytes: maxCachedTilesMemory)
        let determineFeatureStyle = DetermineFeatureStyle(mapStyle: mapStyle)
        tileParser = TileMvtParser(determineFeatureStyle: determineFeatureStyle)
        
        mapNeedsTile = MapNeedsTile(metalTilesStorage: self)
    }
    
    func getMetalTile(tile: Tile) -> MetalTile? {
        return memoryMetalTile.getTile(forKey: tile.key())
    }
    
    func request(tiles: [Tile], hash: inout Int) -> [TileInStorage] {
        var forHash: Set<Tile> = []
        var tilesInStorage: [TileInStorage] = []
        var request: [Tile] = []
        for tile in tiles {
            let metalTile = getMetalTile(tile: tile)
            
            // Готового тайла к отображению нету, его нужно запросить, загрузить с диска или с интернета
            // Так же распарсить и после загрузить в кэш
            if metalTile == nil {
                request.append(tile)
            } else {
                // В хэше учитываем только готовые тайлы
                // При подгрузке нужных тайлов хэш будет меняться и провоцировать перерисовку карты
                forHash.insert(tile)
            }
            
            // Подготавливаем массив отрисовки
            tilesInStorage.append(TileInStorage(metalTile: metalTile, tile: tile))
        }
        
        
        // отправляем все тайлы, которых нету на загрузку
        mapNeedsTile!.request(tiles: request)
        
        hash = forHash.hashValue
        return tilesInStorage
    }
    
    func parseTile(tile: Tile, data: Data) async {
        let parsedTile = tileParser.parse(
            tile: tile,
            mvtData: data
        )
        
        // Parse Text labels
        let textLabels = parsedTile.textLabels
        for label in textLabels {
            var vertices = textRenderer.collectLabelVertices(for: label.text)
            for i in vertices.indices {
                vertices[i].position.x = vertices[i].position.x / 4096.0
                vertices[i].position.y = vertices[i].position.y / 4096.0
            }
            let buffer = metalDevice.makeBuffer(bytes: vertices, length: MemoryLayout<LabelVertex>.stride * vertices.count)
            
        }
        
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
            
            renderer.newTileAvailable(tile: tile)
        }
    }
    
    struct TileInStorage {
        let metalTile: MetalTile?
        let tile: Tile
    }
}
