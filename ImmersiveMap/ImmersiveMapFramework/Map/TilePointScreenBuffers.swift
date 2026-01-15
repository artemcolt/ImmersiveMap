//
//  TilePointScreenBuffers.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class TilePointScreenBuffers {
    private let metalDevice: MTLDevice
    private(set) var inputBuffer: MTLBuffer
    private(set) var outputBuffer: MTLBuffer
    private(set) var tileIndexBuffer: MTLBuffer
    private(set) var pointsCount: Int = 0

    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
        self.inputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<TilePointInput>.stride, options: [.storageModeShared]
        )!
        self.outputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<ScreenPointOutput>.stride, options: [.storageModeShared]
        )!
        self.tileIndexBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UInt32>.stride, options: [.storageModeShared]
        )!
    }

    private func ensureBuffersCapacity(count: Int) {
        let inputNeeded = count * MemoryLayout<TilePointInput>.stride
        if inputBuffer.length < inputNeeded {
            inputBuffer = metalDevice.makeBuffer(length: inputNeeded, options: [.storageModeShared])!
        }

        let outputNeeded = count * MemoryLayout<ScreenPointOutput>.stride
        if outputBuffer.length < outputNeeded {
            outputBuffer = metalDevice.makeBuffer(length: outputNeeded, options: [.storageModeShared])!
        }

        let tileIndexNeeded = count * MemoryLayout<UInt32>.stride
        if tileIndexBuffer.length < tileIndexNeeded {
            tileIndexBuffer = metalDevice.makeBuffer(length: tileIndexNeeded, options: [.storageModeShared])!
        }
    }

    func copyDataToBuffer(inputs: [TilePointInput], tileIndices: [UInt32]) {
        precondition(inputs.count == tileIndices.count, "Tile point inputs and tile indices must match.")
        ensureBuffersCapacity(count: inputs.count)
        let inputBytes = inputs.count * MemoryLayout<TilePointInput>.stride
        inputs.withUnsafeBytes { bytes in
            inputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: inputBytes)
        }

        let tileIndexBytes = tileIndices.count * MemoryLayout<UInt32>.stride
        tileIndices.withUnsafeBytes { bytes in
            tileIndexBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: tileIndexBytes)
        }

        pointsCount = inputs.count
    }
}
