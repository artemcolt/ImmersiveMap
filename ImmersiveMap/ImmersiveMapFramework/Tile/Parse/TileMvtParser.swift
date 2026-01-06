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
        let textLabels: [TextLabel]
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

    struct TextLabel {
        let text: String
        let position: SIMD2<Int16>
        let key: UInt64
        
        init(text: String, position: SIMD2<Int16>, tile: Tile, featureId: UInt64, layerName: String) {
            self.text = text
            self.position = position
            self.key = TextLabel.makeKey(text: text, featureId: featureId, layerName: layerName)
        }
        
        private static func makeKey(text: String, featureId: UInt64, layerName: String) -> UInt64 {
            // Compact, stable FNV-1a hash for a label.
            var hash: UInt64 = 1469598103934665603
            func mix(_ value: UInt64) {
                hash ^= value
                hash &*= 1099511628211
            }
            
            mix(featureId)
            for byte in layerName.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            
            return hash
        }
    }
    
    class ParsedTile {
        let drawingPolygon: DrawingPolygonBytes
        let styles: [TilePolygonStyle]
        let tile: Tile
        let textLabels: [TextLabel]
        
        init(
            drawingPolygon: DrawingPolygonBytes,
            styles: [TilePolygonStyle],
            tile: Tile,
            textLabels: [TextLabel]
        ) {
            self.drawingPolygon = drawingPolygon
            self.styles = styles
            self.tile = tile
            self.textLabels = textLabels
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
            textLabels: readingStageResult.textLabels
        )
    }

    private func decodeZigZag(_ value: UInt32) -> Int32 {
        return Int32(value >> 1) ^ -Int32(value & 1)
    }

    private func decodePoints(geometry: [UInt32]) -> [SIMD2<Int16>] {
        var points: [SIMD2<Int16>] = []
        var cursorX: Int32 = 0
        var cursorY: Int32 = 0
        var index = 0
        
        while index < geometry.count {
            let cmdInteger = geometry[index]
            index += 1
            let cmd = cmdInteger & 0x7
            let count = Int(cmdInteger >> 3)
            
            if cmd == 1 || cmd == 2 {
                for _ in 0..<count {
                    if index + 1 >= geometry.count { break }
                    let dx = decodeZigZag(geometry[index])
                    let dy = decodeZigZag(geometry[index + 1])
                    index += 2
                    cursorX += dx
                    cursorY += dy
                    points.append(SIMD2(Int16(cursorX), Int16(cursorY)))
                }
            } else if cmd == 7 {
                continue
            } else {
                break
            }
        }
        
        return points
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
        var textLabels: [TextLabel] = []
        
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
                } else if feature.type == .point {
                    guard let nameEn = attributes["name_en"]?.stringValue else { continue }
                    let points = decodePoints(geometry: feature.geometry)
                    let featureId = feature.id
                    for point in points {
                        textLabels.append(TextLabel(text: nameEn,
                                                    position: point,
                                                    tile: tile,
                                                    featureId: featureId,
                                                    layerName: layerName))
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
            textLabels: textLabels
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
