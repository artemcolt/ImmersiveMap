//
//  FlatTileOriginCalculator.swift
//  ImmersiveMap
//
//  Created by Artem on 1/4/26.
//

import Metal
import simd

final class FlatTileOriginCalculator {
    private let metalDevice: MTLDevice
    private var tileOriginDataBuffer: MTLBuffer
    private var tileOriginData: [SIMD4<Float>] = []

    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
        self.tileOriginDataBuffer = metalDevice.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride)!
    }

    func update(tiles: [Tile], flatPan: SIMD2<Double>, mapSize: Double) -> MTLBuffer {
        let halfMapSize = mapSize / 2.0
        tileOriginData.removeAll(keepingCapacity: true)
        tileOriginData.reserveCapacity(tiles.count)
        tileOriginData = tiles.map { tile in
            let tilesCount = 1 << tile.z
            let tileSize = mapSize / Double(tilesCount)
            let originX = Double(tile.x) * tileSize - halfMapSize + flatPan.x * halfMapSize + Double(tile.loop) * mapSize
            let originY = Double(tilesCount - tile.y - 1) * tileSize - halfMapSize - flatPan.y * halfMapSize
            return SIMD4<Float>(Float(originX), Float(originY), Float(tileSize), 0)
        }

        let needed = max(1, tileOriginData.count) * MemoryLayout<SIMD4<Float>>.stride
        if tileOriginDataBuffer.length < needed {
            tileOriginDataBuffer = metalDevice.makeBuffer(length: needed)!
        }
        if tileOriginData.isEmpty == false {
            let bytesCount = tileOriginData.count * MemoryLayout<SIMD4<Float>>.stride
            tileOriginData.withUnsafeBytes { bytes in
                tileOriginDataBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytesCount)
            }
        }

        return tileOriginDataBuffer
    }
}
