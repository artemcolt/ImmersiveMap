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
    
    var texture: [MTLTexture] = []
    let size: Int = 1024 * 4
    var cellSize: Int = 1024
    private var projection: matrix_float4x4
    private let tilePipeline: TilePipeline
    private var renderEncoder: MTLRenderCommandEncoder?
    var tileData: [TileData]
    
    private(set) var freePtr: Int = 0
    
    init(metalDevice: MTLDevice, tilePipeline: TilePipeline) {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = size
        descriptor.height = size
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        for _ in 0..<3 {
            texture.append(metalDevice.makeTexture(descriptor: descriptor)!)
        }
        self.tilePipeline = tilePipeline
        
        let count = size / cellSize
        projection = Matrix.orthographicMatrix(left: 0, right: Float(4096 * count), bottom: 0, top: Float(4096 * count), near: -1, far: 1)
        tileData = []
    }
    
    func activateEncoder(commandBuffer: MTLCommandBuffer, index: Int) {
        tileData = []
        freePtr = 0
        cellSize = 1024
        refreshProjectionMatrix()
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture[index]
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        
        renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        tilePipeline.selectPipeline(renderEncoder: renderEncoder!)
    }
    
    func endEncoding() {
        renderEncoder?.endEncoding()
    }
    
    private func refreshProjectionMatrix() {
        let count = size / cellSize
        projection = Matrix.orthographicMatrix(left: 0, right: Float(4096 * count), bottom: 0, top: Float(4096 * count), near: -1, far: 1)
    }
    
    
    func draw(metalTile: MetalTile) -> Bool {
        if freePtr >= 2 * (size / cellSize) && cellSize == 1024 {
            cellSize = 512
            freePtr = size / cellSize * 4
            
            refreshProjectionMatrix()
        }
        
        let count = size / cellSize
        if freePtr > count * count - 1 {
            print("No place for tile")
            return false
        }
        
        let x = freePtr % count
        let y = freePtr / count
        let shiftMatrix = Matrix.translationMatrix(x: Float(x) * 4096, y: Float(y) * 4096, z: 0)
        var cameraUniform = CameraUniform(matrix: projection * shiftMatrix)
        
        guard let renderEncoder = renderEncoder else { return true }
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        
        let buffers = metalTile.tileBuffers
        renderEncoder.setVertexBuffer(buffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(buffers.stylesBuffer, offset: 0, index: 2)
        
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: buffers.indicesCount, indexType: .uint32, indexBuffer: buffers.indicesBuffer, indexBufferOffset: 0)
        
        let tile = metalTile.tile
        tileData.append(TileData(position: simd_int1(freePtr),
                                 textureSize: simd_int1(size),
                                 cellSize: simd_int1(cellSize),
                                 tile: simd_int3(Int32(tile.x), Int32(tile.y), Int32(tile.z))))
        freePtr += 1
        return true
    }
}
