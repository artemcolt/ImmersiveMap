//
//  MetalTilesStorage.swift
//  TucikMap
//
//  Created by Artem on 6/6/25.
//

import Foundation
internal import GISTools
import MetalKit
import simd

class MetalTilesStorage {
    private var mapNeedsTile        : MapNeedsTile?
    var tileParser                  : TileMvtParser!
    private var memoryMetalTile     : MemoryMetalTileCache!
    private let metalDevice         : MTLDevice
    private let debugAssemblingMap  : Bool
    private let renderer            : Renderer
    private let textRenderer        : TextRenderer
    private let config              : MapConfiguration

    private func roadPathAnchor(path: [SIMD2<Int16>]) -> (segmentIndex: Int, t: Float) {
        guard path.count > 1 else {
            return (segmentIndex: 0, t: 0.0)
        }

        var totalLength: Float = 0.0
        var last = SIMD2<Float>(Float(path[0].x), Float(path[0].y))
        for i in 1..<path.count {
            let current = SIMD2<Float>(Float(path[i].x), Float(path[i].y))
            totalLength += simd_length(current - last)
            last = current
        }

        if totalLength <= 0.0 {
            return (segmentIndex: 0, t: 0.0)
        }

        let target = totalLength * 0.5
        var accumulated: Float = 0.0
        last = SIMD2<Float>(Float(path[0].x), Float(path[0].y))
        for i in 1..<path.count {
            let current = SIMD2<Float>(Float(path[i].x), Float(path[i].y))
            let segmentLength = simd_length(current - last)
            if segmentLength > 0.0, accumulated + segmentLength >= target {
                let t = (target - accumulated) / segmentLength
                return (segmentIndex: i - 1, t: t)
            }
            accumulated += segmentLength
            last = current
        }

        return (segmentIndex: max(0, path.count - 2), t: 0.0)
    }
    
    init(
        mapStyle: MapStyle,
        metalDevice: MTLDevice,
        renderer: Renderer,
        textRenderer: TextRenderer,
        config: MapConfiguration
    ) {
        self.metalDevice = metalDevice
        self.renderer = renderer
        self.textRenderer = textRenderer
        self.config = config
        self.debugAssemblingMap = config.debugAssemblingMap
        let maxCachedTilesMemory = config.maxCachedTilesMemInBytes
        memoryMetalTile = MemoryMetalTileCache(maxCacheSizeInBytes: maxCachedTilesMemory)
        let determineFeatureStyle = DetermineFeatureStyle(mapStyle: mapStyle)
        tileParser = TileMvtParser(determineFeatureStyle: determineFeatureStyle, config: config)
        
        mapNeedsTile = MapNeedsTile(metalTilesStorage: self, config: config)
    }
    
    func getMetalTile(tile: Tile) -> MetalTile? {
        return memoryMetalTile.getTile(forKey: tile)
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
        let roadTextLabels = parsedTile.roadTextLabels
        let tileIndices = SIMD3<Int32>(Int32(tile.x), Int32(tile.y), Int32(tile.z))
        var labelsVertices: [LabelVertex] = []
        var tilePointInputs: [TilePointInput] = []
        var labelsMeta: [GlobeLabelMeta] = []
        var labelsVerticesRanges: [LabelVerticesRange] = []
        for i in textLabels.indices {
            let label = textLabels[i]
            let pos = label.position
            let uvX = Double(pos.x) / 4096.0
            let uvY = Double(pos.y) / 4096.0
            let uv = SIMD2<Float>(Float(uvX), Float(uvY))
            
            let textMetrics = textRenderer.collectLabelVertices(for: label.text, labelIndex: simd_int1(i), scale: 60.0)
            
            // Это для отрисовки визуально текста
            let vertices = textMetrics.vertices
            let rangeStart = labelsVertices.count
            labelsVertices.append(contentsOf: vertices)
            labelsVerticesRanges.append(LabelVerticesRange(start: rangeStart, count: vertices.count))
            
            // Это для GPU шейдера массив
            // Тут данные на каждый label
            let size = SIMD2<Float>(textMetrics.size.width, textMetrics.size.height)
            tilePointInputs.append(TilePointInput(uv: uv, tile: tileIndices, size: size))
            
            labelsMeta.append(GlobeLabelMeta(key: label.key))
        }

        var roadPathInputs: [TilePointInput] = []
        var roadPathRanges: [RoadPathRange] = []
        var roadPathLabels: [RoadPathLabel] = []
        var roadLabelBaseVertices: [LabelVertex] = []
        var roadLabelVertexRanges: [LabelVerticesRange] = []
        var roadLabelSizes: [SIMD2<Float>] = []
        roadPathInputs.reserveCapacity(roadTextLabels.count * 4)
        for i in roadTextLabels.indices {
            let roadLabel = roadTextLabels[i]
            let rangeStart = roadPathInputs.count
            for point in roadLabel.path {
                let uvX = Double(point.x) / 4096.0
                let uvY = Double(point.y) / 4096.0
                let uv = SIMD2<Float>(Float(uvX), Float(uvY))
                roadPathInputs.append(TilePointInput(uv: uv,
                                                     tile: tileIndices,
                                                     size: .zero))
            }

            let count = roadPathInputs.count - rangeStart
            if count > 0 {
                let labelIndex = roadPathLabels.count
                let anchor = roadPathAnchor(path: roadLabel.path)
                roadPathLabels.append(RoadPathLabel(text: roadLabel.text, key: roadLabel.key))
                roadPathRanges.append(RoadPathRange(start: rangeStart,
                                                    count: count,
                                                    labelIndex: labelIndex,
                                                    anchorSegmentIndex: anchor.segmentIndex,
                                                    anchorT: anchor.t))

                let textMetrics = textRenderer.collectLabelVertices(for: roadLabel.text,
                                                                    labelIndex: simd_int1(i),
                                                                    scale: 60.0)
                let vertexStart = roadLabelBaseVertices.count
                roadLabelBaseVertices.append(contentsOf: textMetrics.vertices)
                roadLabelVertexRanges.append(LabelVerticesRange(start: vertexStart, count: textMetrics.vertices.count))
                roadLabelSizes.append(SIMD2<Float>(textMetrics.size.width, textMetrics.size.height))
            }
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
            // текстовые метки
            tilePointInputs: tilePointInputs,
            labelsVertices: labelsVertices,
            labelsVerticesRanges: labelsVerticesRanges,
            labelsVerticesBuffer: labelsBuffer,
            labelsCount: textLabels.count,
            labelsVerticesCount: labelsVertices.count,
            labelsMeta: labelsMeta,
            roadPathInputs: roadPathInputs,
            roadPathRanges: roadPathRanges,
            roadPathLabels: roadPathLabels,
            roadLabelBaseVertices: roadLabelBaseVertices,
            roadLabelVertexRanges: roadLabelVertexRanges,
            roadLabelSizes: roadLabelSizes
        )
        
        let metalTile = MetalTile(tile: tile, tileBuffers: tileBuffers)
        
        await MainActor.run {
            self.memoryMetalTile.setTileData(
                tile: metalTile,
                forKey: tile
            )
            
            renderer.newTileAvailable(tile: tile)
        }
    }
    
    struct TileInStorage {
        let metalTile: MetalTile?
        let tile: Tile
    }
}
