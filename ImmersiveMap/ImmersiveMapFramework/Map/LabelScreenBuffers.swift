//
//  LabelScreenBuffers.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal
import simd

final class LabelScreenBuffers {
    private let metalDevice: MTLDevice
    private(set) var inputBuffer: MTLBuffer
    private(set) var outputBuffer: MTLBuffer
    private(set) var collisionInputBuffer: MTLBuffer
    private(set) var inputsCount: Int = 0

    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
        self.inputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<LabelInput>.stride, options: [.storageModeShared]
        )!
        self.outputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeScreenPointOutput>.stride, options: [.storageModeShared]
        )!
        self.collisionInputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<ScreenCollisionInput>.stride, options: [.storageModeShared]
        )!
    }

    private func ensureBuffersCapacity(count: Int) {
        let inputNeeded = count * MemoryLayout<LabelInput>.stride
        if inputBuffer.length < inputNeeded {
            inputBuffer = metalDevice.makeBuffer(length: inputNeeded, options: [.storageModeShared])!
        }

        let outputNeeded = count * MemoryLayout<GlobeScreenPointOutput>.stride
        if outputBuffer.length < outputNeeded {
            outputBuffer = metalDevice.makeBuffer(length: outputNeeded, options: [.storageModeShared])!
        }

        let collisionNeeded = count * MemoryLayout<ScreenCollisionInput>.stride
        if collisionInputBuffer.length < collisionNeeded {
            collisionInputBuffer = metalDevice.makeBuffer(length: collisionNeeded, options: [.storageModeShared])!
        }
    }

    func copyDataToBuffer(inputs: [LabelInput]) {
        ensureBuffersCapacity(count: inputs.count)
        let inputBytes = inputs.count * MemoryLayout<LabelInput>.stride
        inputs.withUnsafeBytes { bytes in
            inputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: inputBytes)
        }

        var collisionInputs: [ScreenCollisionInput] = []
        collisionInputs.reserveCapacity(inputs.count)
        for input in inputs {
            let halfSize = SIMD2<Float>(input.size.x * 0.5, input.size.y * 0.5)
            collisionInputs.append(ScreenCollisionInput(halfSize: halfSize,
                                                        radius: 0.0,
                                                        shapeType: .rect))
        }
        let collisionBytes = collisionInputs.count * MemoryLayout<ScreenCollisionInput>.stride
        collisionInputs.withUnsafeBytes { bytes in
            collisionInputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: collisionBytes)
        }
        inputsCount = inputs.count
    }
}
