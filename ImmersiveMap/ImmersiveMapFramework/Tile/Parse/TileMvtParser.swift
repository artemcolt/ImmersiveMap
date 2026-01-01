//
//  MVTTileParser.swift
//  TucikMap
//
//  Created by Artem on 5/28/25.
//

import Foundation
import MetalKit
internal import SwiftEarcut


class TileMvtParser {
    private let determineFeatureStyle       : DetermineFeatureStyle
    private let parsePolygon                : ParsePolygon = ParsePolygon()
    private let decodePolygon               : DecodePolygon = DecodePolygon()
    private let parseLine                   : ParseLine = ParseLine()
    private let decodeLine                  : DecodeLine = DecodeLine()
    let tileExtent = Double(4096)
    
    
    struct ReadingStageResult {
        let polygonByStyle: [UInt8: [ParsedPolygon]]
        let rawLineByStyle: [UInt8: [ParsedLineRawVertices]]
        let styles: [UInt8: FeatureStyle]
    }
    
    struct ParseGeometryStyleData {
        let lineWidth: Double
    }
    
    struct ParsedPolygon {
        var vertices: [SIMD2<Int16>] = []
        var indices: [UInt32] = []
    }
    
    struct ParsedLineRawVertices {
        let vertices: [SIMD3<Float>]
        let indices: [UInt32]
    }
    
    struct UnificationStageResult {
        var drawingPolygon: DrawingPolygonBytes
        var styles: [TilePolygonStyle]
    }
    
    struct DrawingPolygonBytes {
        var vertices: [TilePipeline.VertexIn]
        var indices: [UInt32]
    }
    
    class ParsedTile {
        let drawingPolygon: DrawingPolygonBytes
        let styles: [TilePolygonStyle]
        let tile: Tile
        
        init(
            drawingPolygon: DrawingPolygonBytes,
            styles: [TilePolygonStyle],
            tile: Tile,
        ) {
            self.drawingPolygon = drawingPolygon
            self.styles = styles
            self.tile = tile
        }
    }
    
    init(determineFeatureStyle: DetermineFeatureStyle) {
        self.determineFeatureStyle = determineFeatureStyle
    }
    
    func parse(
        tile: Tile,
        mvtData: Data
    ) -> ParsedTile {
        let vectorTile = try! VectorTile_Tile(serializedBytes: mvtData)
        
        let readingStageResult = readingStage(vectorTile: vectorTile, tile: tile)
        let unificationResult = unificationStage(readingStageResult: readingStageResult)
        
        return ParsedTile(
            drawingPolygon: unificationResult.drawingPolygon,
            styles: unificationResult.styles,
            tile: tile,
        )
    }
    
    private func addBorder(polygonByStyle: inout [UInt8: [ParsedPolygon]], styles: inout [UInt8: FeatureStyle], borderWidth: Int16) {
        let style = determineFeatureStyle.makeStyle(data: DetFeatureStyleData(
            layerName: "border",
            properties: [:],
            tile: Tile(x: 0, y: 0, z: 0))
        )
        
        let tileSize: Int16 = 4096
        var polygons = [ParsedPolygon]()
        
        // Bottom border
        var vertices: [SIMD2<Int16>] = [
            SIMD2(0, 0),
            SIMD2(tileSize, 0),
            SIMD2(0, borderWidth),
            SIMD2(tileSize, borderWidth)
        ]
        var indices: [UInt32] = [0, 2, 1, 1, 2, 3]
        polygons.append(ParsedPolygon(vertices: vertices, indices: indices))
        
        // Top border
        vertices = [
            SIMD2(0, tileSize - borderWidth),
            SIMD2(tileSize, tileSize - borderWidth),
            SIMD2(0, tileSize),
            SIMD2(tileSize, tileSize)
        ]
        indices = [0, 2, 1, 1, 2, 3]
        polygons.append(ParsedPolygon(vertices: vertices, indices: indices))
        
        // Left border
        vertices = [
            SIMD2(0, 0),
            SIMD2(borderWidth, 0),
            SIMD2(0, tileSize),
            SIMD2(borderWidth, tileSize)
        ]
        indices = [0, 2, 1, 1, 2, 3]
        polygons.append(ParsedPolygon(vertices: vertices, indices: indices))
        
        // Right border
        vertices = [
            SIMD2(tileSize - borderWidth, 0),
            SIMD2(tileSize, 0),
            SIMD2(tileSize - borderWidth, tileSize),
            SIMD2(tileSize, tileSize)
        ]
        indices = [0, 2, 1, 1, 2, 3]
        polygons.append(ParsedPolygon(vertices: vertices, indices: indices))
        
        polygonByStyle[style.key] = polygons
        styles[style.key] = style
    }
    
    private func addBackground(polygonByStyle: inout [UInt8: [ParsedPolygon]], styles: inout [UInt8: FeatureStyle]) {
        let style = determineFeatureStyle.makeStyle(data: DetFeatureStyleData(
            layerName: "background",
            properties: [:],
            tile: Tile(x: 0, y: 0, z: 0))
        )
        
        let numSegments: Int = 64 // Adjustable number of segments per side; change as needed
        let step: Int16 = Int16(4096 / numSegments)

        // Generate vertices: (numSegments + 1) x (numSegments + 1) grid
        var vertices = [SIMD2<Int16>]()
        for i in 0...numSegments {
            for j in 0...numSegments {
                let x = Int16(i) * step
                let y = Int16(j) * step
                vertices.append(SIMD2(x, y))
            }
        }

        // Generate indices for triangles: two triangles per quad
        var indices = [UInt32]()
        let numVerticesPerRow = UInt32(numSegments + 1)
        for i in 0..<numSegments {
            for j in 0..<numSegments {
                let a = UInt32(i * Int(numVerticesPerRow) + j)
                let b = a + 1
                let c = UInt32((i + 1) * Int(numVerticesPerRow) + j)
                let d = c + 1
                
                // First triangle: a -> c -> b (counter-clockwise assuming y-up)
                indices.append(a)
                indices.append(c)
                indices.append(b)
                
                // Second triangle: b -> c -> d (counter-clockwise assuming y-up)
                indices.append(b)
                indices.append(c)
                indices.append(d)
            }
        }

        let parsedPolygon = ParsedPolygon(vertices: vertices, indices: indices)
        
        polygonByStyle[style.key] = [parsedPolygon]
        styles[style.key] = style
    }
    
    
    func readingStage(vectorTile: VectorTile_Tile, tile: Tile) -> ReadingStageResult {
        var polygonByStyle: [UInt8: [ParsedPolygon]] = [:]
        var rawLineByStyle: [UInt8: [ParsedLineRawVertices]] = [:]
        var styles: [UInt8: FeatureStyle] = [:]
        
        for layer in vectorTile.layers {
            let layerName = layer.name
            for feature in layer.features {
                
                var attributes: [String: VectorTile_Tile.Value] = [:]
                for i in stride(from: 0, to: feature.tags.count, by: 2) {
                    guard i + 1 < feature.tags.count else { break }
                    let keyIndex = Int(feature.tags[i])
                    let valueIndex = Int(feature.tags[i + 1])
                    
                    guard keyIndex < layer.keys.count,
                          valueIndex < layer.values.count else { continue }
                    
                    let key = layer.keys[keyIndex]
                    let value = layer.values[valueIndex]
                    
                    attributes[key] = value
                }
                
                let detStyleData = DetFeatureStyleData(
                    layerName: layerName,
                    properties: attributes,
                    tile: tile
                )
                
                let style = determineFeatureStyle.makeStyle(data: detStyleData)
                let styleKey = style.key
                if styleKey == 0 {
                    // none defineded style
                    continue
                }
                if styles[styleKey] == nil {
                    styles[styleKey] = style
                }
                
                if feature.type == .polygon {
                    let geometry: [UInt32] = feature.geometry
                    let polygons = decodePolygon.decode(geometry: geometry)
                    
                    for polygon in polygons {
                        guard let parsedPolygon = parsePolygon.parse(polygon: polygon, tileExtent: Float(tileExtent)) else { continue }
                        polygonByStyle[styleKey, default: []].append(parsedPolygon)
                    }
                } else if feature.type == .linestring {
                    let geometry: [UInt32] = feature.geometry
                    let width = style.parseGeometryStyleData.lineWidth
                    if width <= 0 {
                        continue
                    }
                    
                    let lines = decodeLine.decode(geometry: geometry)
                    for line in lines {
                        let linePolygons = parseLine.parse(line: line, width: width, tileExtent: Float(tileExtent))
                        if linePolygons.isEmpty == false {
                            polygonByStyle[styleKey, default: []].append(contentsOf: linePolygons)
                        }
                    }
                }
            }
        }
        
        addBackground(polygonByStyle: &polygonByStyle, styles: &styles)
        if (MapParameters.addTestBorders) { addBorder(polygonByStyle: &polygonByStyle, styles: &styles, borderWidth: 1) }
        
        return ReadingStageResult(
            polygonByStyle: polygonByStyle.filter { $0.value.isEmpty == false },
            rawLineByStyle: rawLineByStyle.filter { $0.value.isEmpty == false },
            styles: styles,
        )
    }
    
    func unificationStage(readingStageResult: ReadingStageResult) -> UnificationStageResult {
        let polygonByStyle = readingStageResult.polygonByStyle
        let rawLineByStyle = readingStageResult.rawLineByStyle
        
        var unifiedVertices: [TilePipeline.VertexIn] = []
        var unifiedIndices: [UInt32] = []
        var currentVertexOffset: UInt32 = 0
        var styles: [TilePolygonStyle] = []
        
        var styleBufferIndex: simd_uchar1 = 0
        for styleKey in readingStageResult.styles.keys.sorted() {
            if let polygons = polygonByStyle[styleKey] {
                // Process each polygon for the current style
                for polygon in polygons {
                    // Append vertices to unified array
                    unifiedVertices.append(contentsOf: polygon.vertices.map {
                        position in TilePipeline.VertexIn(position: position, styleIndex: styleBufferIndex)
                    })
                    
                    // Adjust indices for the current polygon and append
                    let adjustedIndices = polygon.indices.map { index in
                        return index + currentVertexOffset
                    }
                    unifiedIndices.append(contentsOf: adjustedIndices)
                    
                    // Update vertex offset for the next polygon
                    currentVertexOffset += UInt32(polygon.vertices.count)
                }
            }
            
//            if let rawLines = rawLineByStyle[styleKey] {
//                for rawLine in rawLines {
//                    // Append vertices to unified array
//                    unifiedVertices.append(contentsOf: rawLine.vertices.map {
//                        position in TilePipeline.VertexIn(position: position, styleIndex: styleBufferIndex)
//                    })
//                    
//                    // Adjust indices for the current polygon and append
//                    let adjustedIndices = rawLine.indices.map { index in
//                        return index + currentVertexOffset
//                    }
//                    unifiedIndices.append(contentsOf: adjustedIndices)
//                    
//                    // Update vertex offset for the next polygon
//                    currentVertexOffset += UInt32(rawLine.vertices.count)
//                }
//            }
            
            let style = readingStageResult.styles[styleKey]!
            styles.append(TilePolygonStyle(color: style.color))
            styleBufferIndex += 1
        }
        
        return UnificationStageResult(
            drawingPolygon: DrawingPolygonBytes(
                vertices: unifiedVertices,
                indices: unifiedIndices
            ),
            styles: styles
        )
    }
}
