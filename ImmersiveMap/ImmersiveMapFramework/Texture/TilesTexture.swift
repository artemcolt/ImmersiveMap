//
//  TilesTexture.swift
//  ImmersiveMap
//
//  Created by Artem on 9/19/25.
//

import MetalKit

class TilesTexture {
    struct TileData {
        let position: simd_int1
        let textureSize: simd_int1
        let cellSize: simd_int1
        let tile: simd_int3
    }
    
    let textSize: Float = 40
    var texture: [MTLTexture] = []
    let size: Int = 4096
    var cellSize: Int = 1024
    var projection: matrix_float4x4
    private let tilePipeline: TilePipeline
    var renderEncoder: MTLRenderCommandEncoder?
    var tileData: [TileData]
    var texts: [TextEntry] = []
    var textsMatrices: [matrix_float4x4] = []
    private var textureTree: TextureTree
    
    private var previousShiftX: Float? = nil
    private var previousShiftY: Float? = nil
    private var previousScale: Float? = nil
    
    init(metalDevice: MTLDevice, tilePipeline: TilePipeline) {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = size
        descriptor.height = size
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        for _ in 0..<1 {
            texture.append(metalDevice.makeTexture(descriptor: descriptor)!)
        }
        self.tilePipeline = tilePipeline
        
        let count = size / cellSize
        projection = Matrix.orthographicMatrix(left: 0, right: Float(4096 * count), bottom: 0, top: Float(4096 * count), near: -1, far: 1)
        tileData = []
        textureTree = TextureTree()
    }
    
    func activateEncoder(commandBuffer: MTLCommandBuffer, index: Int) {
        previousShiftX = nil
        previousShiftY = nil
        previousScale = nil
        textureTree = TextureTree()
        tileData = []
        texts = []
        textsMatrices = []
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture[index]
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        
        renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    }
    
    func selectTilePipeline() {
        tilePipeline.selectPipeline(renderEncoder: renderEncoder!)
    }
    
    func endEncoding() {
        renderEncoder?.endEncoding()
    }
    
    private func refreshProjectionMatrix(count: Int) {
        projection = Matrix.orthographicMatrix(left: 0, right: Float(4096 * count), bottom: 0, top: Float(4096 * count), near: -1, far: 1)
    }
    
    func draw(placeTile: Renderer.PlaceTile, depth: UInt8, maxDepth: UInt8) -> Bool {
        guard let placedPos = textureTree.addNewValue(value: TextureValue(), depth: depth) else { return false }
        guard let renderEncoder = renderEncoder else { return true }
        
        let metalTile = placeTile.metalTile
        let placeIn = placeTile.placeIn
        
        let count = 1 << depth
        let cellSize = size / count
        let freePtr = Int(placedPos.x) + Int(placedPos.y) * count
        
        refreshProjectionMatrix(count: count)
        
        let x = Int(placedPos.x)
        let y = Int(placedPos.y)
        let shiftMatrix = Matrix.translationMatrix(x: Float(x) * 4096, y: Float(y) * 4096, z: 0)
        var cameraUniform = CameraUniform(matrix: projection * shiftMatrix)
        let scaleParam = Float( 1 << (UInt8(maxDepth) - depth))
        let shift = scaleParam * 10
        
        let placeInCount = 1 << placeIn.z
        let zDiff = placeIn.z - metalTile.tile.z
        let scale = powf(2.0, Float(zDiff))
        
        let mtCount = 1 << metalTile.tile.z
        
        
        let relX = Float(placeIn.x) - (Float(metalTile.tile.x) * scale)
        let relY = Float(placeIn.y) + (Float((mtCount - 1) - metalTile.tile.y) * scale)
        
        let shiftX = -1.0 * Float(relX) * 4096.0
        let shiftY = -1.0 * Float(Float(placeInCount - 1) - relY) * 4096.0
        if shiftX != previousShiftX || shiftY != previousShiftY || scale != previousScale {
            var modelMatrix = Matrix.translationMatrix(x: shiftX, y: shiftY, z: 0) * Matrix.scaleMatrix(sx: scale, sy: scale, sz: 1)
            renderEncoder.setVertexBytes(&modelMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 3)
        }
        
        previousShiftX = shiftX
        previousShiftY = shiftY
        previousScale = scale
        
        let tile = placeIn
        texts.append(TextEntry(
            text: "x: \(tile.x) y: \(tile.y) z: \(tile.z)",
            position: SIMD2<Float>(Float(x) * 4096 / Float(count) + shift, Float(y) * 4096 / Float(count) + shift),
            scale: textSize * scaleParam
        ))
        
        let scissorRect = MTLScissorRect(
            x: Int(placedPos.x) * cellSize,
            y: ((count - 1) - Int(placedPos.y)) * cellSize,
            width: cellSize,
            height: cellSize
        )
        
        renderEncoder.setScissorRect(scissorRect)
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        
        let buffers = metalTile.tileBuffers
        renderEncoder.setVertexBuffer(buffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(buffers.stylesBuffer, offset: 0, index: 2)
        
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: buffers.indicesCount, indexType: .uint32, indexBuffer: buffers.indicesBuffer, indexBufferOffset: 0)
        
        tileData.append(TileData(position: simd_int1(freePtr),
                                 textureSize: simd_int1(size),
                                 cellSize: simd_int1(cellSize),
                                 tile: simd_int3(Int32(tile.x), Int32(tile.y), Int32(tile.z))))
        return true
    }
}
