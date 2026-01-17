//
//  TextRenderer.swift
//  ImmersiveMap
//
//  Created by Artem on 11/2/25.
//

import MetalKit
import Foundation

struct TextSize {
    let width: simd_float1
    let height: simd_float1
}

struct TextMetrics {
    let size: TextSize
    let vertices: [LabelVertex]
}

struct AtlasData: Codable {
    let atlas: AtlasInfo
    let metrics: Metrics
    let glyphs: [Glyph]
}

struct AtlasInfo: Codable {
    let type: String
    let distanceRange: CGFloat
    let distanceRangeMiddle: CGFloat
    let size: CGFloat
    let width: Int
    let height: Int
    let yOrigin: String
}

struct Metrics: Codable {
    let emSize: CGFloat
    let lineHeight: CGFloat
    let ascender: CGFloat
    let descender: CGFloat
    let underlineY: CGFloat
    let underlineThickness: CGFloat
}

struct Glyph: Codable {
    let unicode: UInt32
    let advance: CGFloat
    var planeBounds: Bounds?
    var atlasBounds: Bounds?
    
    enum CodingKeys: String, CodingKey {
        case unicode, advance, planeBounds = "planeBounds", atlasBounds = "atlasBounds"
    }
}

struct Bounds: Codable {
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat
    let top: CGFloat
}

struct TextVertex {
    var position: SIMD4<Float> // x, y, z=0, w=1
    var uv: SIMD2<Float>
}

struct LabelVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var labelIndex: simd_int1
}

struct TextEntry {
    let text: String
    let position: SIMD2<Float>
    let scale: Float
    
    init(text: String, position: SIMD2<Float>, scale: Float = 1.0) {
        self.text = text
        self.position = position
        self.scale = scale
    }
}

class TextRenderer {
    private var device: MTLDevice!
    var texture: MTLTexture!
    private var commandQueue: MTLCommandQueue!
    private var bundle: Bundle!
    var atlasData: AtlasData!
    var pipelineState: MTLRenderPipelineState!
    var labelPipelineState: MTLRenderPipelineState!
    var roadLabelPipelineState: MTLRenderPipelineState!
    private var library: MTLLibrary
    
    init(device: MTLDevice, library: MTLLibrary) {
        self.device = device
        self.library = library
        self.commandQueue = device.makeCommandQueue()!
        self.bundle = Bundle(for: ImmersiveMapUIView.self)
        
        loadAtlasTexture()
        loadAtlasJSON()
        createPipelines()
    }
    
    func collectMultiTextVertices(for entries: [TextEntry]) -> [TextVertex] {
        var allVertices: [TextVertex] = []
        
        for entry in entries {
            let textVertices = collectTextVertices(for: entry.text, at: entry.position, scale: entry.scale)
            if !textVertices.isEmpty {
                allVertices.append(contentsOf: textVertices)
            }
        }
        
        return allVertices
    }
    
    func collectLabelVertices(for text: String, labelIndex: simd_int1, scale: Float) -> TextMetrics {
        var vertices: [LabelVertex] = []
        var currentX: Float = 0.0
        let y: Float = 0.0  // Базовая линия на position.y
        let glyphs = atlasData.glyphs
        var width: Float = 0.0
        var height: Float = 0.0
        
        for char in text.unicodeScalars {
            guard let glyph = glyphs.first(where: { $0.unicode == char.value }) else {
                currentX += Float(atlasData.metrics.emSize) * scale * 0.25
                continue
            }
            
            guard let atlasBounds = glyph.atlasBounds else {
                currentX += Float(glyph.advance) * scale
                continue
            }
            
            // Всегда используем planeBounds для позиционирования и размера, если доступно
            let planeLeft = Float(glyph.planeBounds?.left ?? 0)
            let planeBottom = Float(glyph.planeBounds?.bottom ?? 0)
            let planeRight = Float(glyph.planeBounds?.right ?? CGFloat(planeLeft))  // Избегаем нулевой ширины
            let planeTop = Float(glyph.planeBounds?.top ?? CGFloat(planeBottom))
            
            let glyphWidth = planeRight - planeLeft
            let glyphHeight = planeTop - planeBottom
            
            let left = currentX + planeLeft * scale
            let bottom = y + planeBottom * scale
            let right = left + glyphWidth * scale
            let top = bottom + glyphHeight * scale
            
            let atlasLeft = Float(atlasBounds.left) / Float(atlasData.atlas.width)
            let atlasBottom = 1.0 - Float(atlasBounds.bottom) / Float(atlasData.atlas.height)
            let atlasRight = Float(atlasBounds.right) / Float(atlasData.atlas.width)
            let atlasTop = 1.0 - Float(atlasBounds.top) / Float(atlasData.atlas.height)
            
            // Добавляем 6 вертексов для двух треугольников (BL-BR-TL и BR-TR-TL)
            let quadVertices = [
                LabelVertex(position: SIMD2<Float>(left, bottom), uv: SIMD2<Float>(atlasLeft, atlasBottom), labelIndex: labelIndex),  // BL
                LabelVertex(position: SIMD2<Float>(right, bottom), uv: SIMD2<Float>(atlasRight, atlasBottom), labelIndex: labelIndex), // BR
                LabelVertex(position: SIMD2<Float>(left, top), uv: SIMD2<Float>(atlasLeft, atlasTop), labelIndex: labelIndex),         // TL
                
                LabelVertex(position: SIMD2<Float>(right, bottom), uv: SIMD2<Float>(atlasRight, atlasBottom), labelIndex: labelIndex), // BR (дубликат)
                LabelVertex(position: SIMD2<Float>(right, top), uv: SIMD2<Float>(atlasRight, atlasTop), labelIndex: labelIndex),        // TR
                LabelVertex(position: SIMD2<Float>(left, top), uv: SIMD2<Float>(atlasLeft, atlasTop), labelIndex: labelIndex)           // TL (дубликат)
            ]
            
            vertices.append(contentsOf: quadVertices)
            currentX += Float(glyph.advance) * scale
            
            if right > width {
                width = right
            }
            
            if top > height {
                height = top
            }
        }
        
        return TextMetrics(size: TextSize(width: width, height: height), vertices: vertices)
    }
    
    func collectTextVertices(for text: String, at position: SIMD2<Float>, scale: Float = 1.0) -> [TextVertex] {
        var vertices: [TextVertex] = []
        var currentX: Float = position.x
        let lineHeight = Float(atlasData.metrics.lineHeight) * scale
        let y = position.y  // Базовая линия на position.y
        let glyphs = atlasData.glyphs
        
        for char in text.unicodeScalars {
            guard let glyph = glyphs.first(where: { $0.unicode == char.value }) else {
                currentX += Float(atlasData.metrics.emSize) * scale * 0.25
                continue
            }
            
            guard let atlasBounds = glyph.atlasBounds else {
                currentX += Float(glyph.advance) * scale
                continue
            }
            
            // Всегда используем planeBounds для позиционирования и размера, если доступно
            let planeLeft = Float(glyph.planeBounds?.left ?? 0)
            let planeBottom = Float(glyph.planeBounds?.bottom ?? 0)
            let planeRight = Float(glyph.planeBounds?.right ?? CGFloat(planeLeft))  // Избегаем нулевой ширины
            let planeTop = Float(glyph.planeBounds?.top ?? CGFloat(planeBottom))
            
            let glyphWidth = planeRight - planeLeft
            let glyphHeight = planeTop - planeBottom
            
            let left = currentX + planeLeft * scale
            let bottom = y + planeBottom * scale
            let right = left + glyphWidth * scale
            let top = bottom + glyphHeight * scale
            
            let atlasLeft = Float(atlasBounds.left) / Float(atlasData.atlas.width)
            let atlasBottom = 1.0 - Float(atlasBounds.bottom) / Float(atlasData.atlas.height)
            let atlasRight = Float(atlasBounds.right) / Float(atlasData.atlas.width)
            let atlasTop = 1.0 - Float(atlasBounds.top) / Float(atlasData.atlas.height)
            
            // Добавляем 6 вертексов для двух треугольников (BL-BR-TL и BR-TR-TL)
            let quadVertices = [
                TextVertex(position: SIMD4<Float>(left, bottom, 0, 1), uv: SIMD2<Float>(atlasLeft, atlasBottom)),  // BL
                TextVertex(position: SIMD4<Float>(right, bottom, 0, 1), uv: SIMD2<Float>(atlasRight, atlasBottom)), // BR
                TextVertex(position: SIMD4<Float>(left, top, 0, 1), uv: SIMD2<Float>(atlasLeft, atlasTop)),         // TL
                
                TextVertex(position: SIMD4<Float>(right, bottom, 0, 1), uv: SIMD2<Float>(atlasRight, atlasBottom)), // BR (дубликат)
                TextVertex(position: SIMD4<Float>(right, top, 0, 1), uv: SIMD2<Float>(atlasRight, atlasTop)),        // TR
                TextVertex(position: SIMD4<Float>(left, top, 0, 1), uv: SIMD2<Float>(atlasLeft, atlasTop))           // TL (дубликат)
            ]
            
            vertices.append(contentsOf: quadVertices)
            currentX += Float(glyph.advance) * scale
        }
        
        return vertices
    }
    
    private func loadAtlasTexture() {
        guard let url = bundle.url(forResource: "atlas", withExtension: "png") else {
            texture = makeFallbackTexture()
            return
        }
        let textureLoader = MTKTextureLoader(device: device)
        do {
            texture = try textureLoader.newTexture(URL: url, options: nil)
            print("Atlas texture loaded: \(texture.width)x\(texture.height)")
        } catch {
            texture = makeFallbackTexture()
        }
    }
    
    private func loadAtlasJSON() {
        guard let url = bundle.url(forResource: "atlas", withExtension: "json") else {
            atlasData = makeFallbackAtlasData()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            atlasData = try JSONDecoder().decode(AtlasData.self, from: data)
            print("Atlas JSON loaded: \(atlasData.glyphs.count) glyphs")
        } catch {
            atlasData = makeFallbackAtlasData()
        }
    }

    private func makeFallbackTexture() -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = 1
        descriptor.height = 1
        descriptor.usage = [.shaderRead]
        return device.makeTexture(descriptor: descriptor)!
    }

    private func makeFallbackAtlasData() -> AtlasData {
        return AtlasData(
            atlas: AtlasInfo(type: "fallback",
                             distanceRange: 0,
                             distanceRangeMiddle: 0,
                             size: 1,
                             width: 1,
                             height: 1,
                             yOrigin: "bottom"),
            metrics: Metrics(emSize: 1,
                             lineHeight: 1,
                             ascender: 0,
                             descender: 0,
                             underlineY: 0,
                             underlineThickness: 0),
            glyphs: []
        )
    }
    
    private func createPipelines() {
        guard let textVertexFn = library.makeFunction(name: "textVertex"),
              let labelVertexFn = library.makeFunction(name: "labelTextVertex"),
              let roadLabelVertexFn = library.makeFunction(name: "roadLabelTextVertex"),
              let fragmentFn = library.makeFunction(name: "textFragment") else { fatalError("Functions not found") }
        
        let textVertexDescriptor = MTLVertexDescriptor()
        textVertexDescriptor.attributes[0].format = .float4
        textVertexDescriptor.attributes[0].offset = 0
        textVertexDescriptor.attributes[0].bufferIndex = 0
        textVertexDescriptor.attributes[1].format = .float2
        textVertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
        textVertexDescriptor.attributes[1].bufferIndex = 0
        textVertexDescriptor.layouts[0].stride = MemoryLayout<TextVertex>.stride
        
        let labelVertexDescriptor = MTLVertexDescriptor()
        labelVertexDescriptor.attributes[0].format = .float2
        labelVertexDescriptor.attributes[0].offset = 0
        labelVertexDescriptor.attributes[0].bufferIndex = 0
        labelVertexDescriptor.attributes[1].format = .float2
        labelVertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        labelVertexDescriptor.attributes[1].bufferIndex = 0
        labelVertexDescriptor.attributes[2].format = .int
        labelVertexDescriptor.attributes[2].offset = MemoryLayout<SIMD2<Float>>.stride * 2
        labelVertexDescriptor.attributes[2].bufferIndex = 0
        labelVertexDescriptor.layouts[0].stride = MemoryLayout<LabelVertex>.stride
        
        do {
            pipelineState = try makePipelineState(vertexFunction: textVertexFn,
                                                  vertexDescriptor: textVertexDescriptor,
                                                  fragmentFunction: fragmentFn)
            labelPipelineState = try makePipelineState(vertexFunction: labelVertexFn,
                                                       vertexDescriptor: labelVertexDescriptor,
                                                       fragmentFunction: fragmentFn)
            roadLabelPipelineState = try makePipelineState(vertexFunction: roadLabelVertexFn,
                                                           vertexDescriptor: labelVertexDescriptor,
                                                           fragmentFunction: fragmentFn)
        } catch {
            fatalError("Pipeline creation failed: \(error)")
        }
    }
    
    private func makePipelineState(vertexFunction: MTLFunction,
                                   vertexDescriptor: MTLVertexDescriptor,
                                   fragmentFunction: MTLFunction) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
