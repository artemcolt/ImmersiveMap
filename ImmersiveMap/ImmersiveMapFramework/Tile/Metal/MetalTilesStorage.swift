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
        var labelsVertices: [LabelVertex] = []
        var labelsInputs: [GlobeLabelInput] = []
        for i in textLabels.indices {
            let label = textLabels[i]
            let pos = label.position
            let uvX = Double(pos.x) / 4096.0
            let uvY = Double(pos.y) / 4096.0
            let uv = SIMD2<Float>(Float(uvX), Float(uvY))
            let tile = SIMD3<Int32>(Int32(tile.x), Int32(tile.y), Int32(tile.z))
            
            let textMetrics = textRenderer.collectLabelVertices(for: label.text, labelIndex: simd_int1(i), scale: 60.0)
            let vertices = textMetrics.vertices
            labelsVertices.append(contentsOf: vertices)
            
            let size = SIMD2<Float>(textMetrics.size.width, textMetrics.size.height)
            labelsInputs.append(GlobeLabelInput(uv: uv, tile: tile, size: size))
        }
        
        let labelsBuffer: MTLBuffer?
        if labelsVertices.count > 0 {
            labelsBuffer = metalDevice.makeBuffer(bytes: labelsVertices, length: MemoryLayout<LabelVertex>.stride * labelsVertices.count)
        } else {
            labelsBuffer = nil
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
            verticesCount: parsedTile.drawingPolygon.vertices.count,
            labelsInputs: labelsInputs,
            labelsVerticesBuffer: labelsBuffer,
            labelsCount: textLabels.count,
            labelsVerticesCount: labelsVertices.count
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
