//
//  LabelScreenBuffers.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Metal

final class LabelScreenBuffers {
    private let metalDevice: MTLDevice
    private(set) var inputBuffer: MTLBuffer
    private(set) var outputBuffer: MTLBuffer
    private(set) var inputsCount: Int = 0

    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
        self.inputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeLabelInput>.stride, options: [.storageModeShared]
        )!
        self.outputBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<GlobeScreenPointOutput>.stride, options: [.storageModeShared]
        )!
    }

    private func ensureBuffersCapacity(count: Int) {
        let inputNeeded = count * MemoryLayout<GlobeLabelInput>.stride
        if inputBuffer.length < inputNeeded {
            inputBuffer = metalDevice.makeBuffer(length: inputNeeded, options: [.storageModeShared])!
        }

        let outputNeeded = count * MemoryLayout<GlobeScreenPointOutput>.stride
        if outputBuffer.length < outputNeeded {
            outputBuffer = metalDevice.makeBuffer(length: outputNeeded, options: [.storageModeShared])!
        }
    }

    func copyDataToBuffer(inputs: [GlobeLabelInput]) {
        ensureBuffersCapacity(count: inputs.count)
        let inputBytes = inputs.count * MemoryLayout<GlobeLabelInput>.stride
        inputs.withUnsafeBytes { bytes in
            inputBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: inputBytes)
        }
        inputsCount = inputs.count
    }
}
