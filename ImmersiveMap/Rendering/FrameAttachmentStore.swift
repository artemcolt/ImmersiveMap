// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Metal

final class FrameAttachmentStore {
    private let metalDevice: MTLDevice
    private var depthTexture: MTLTexture?
    private var buildingWinnerIDTexture: MTLTexture?
    private var buildingWinnerDepthTexture: MTLTexture?

    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
    }

    var currentBuildingWinnerIDTexture: MTLTexture? {
        buildingWinnerIDTexture
    }

    func ensureDepthTexture(drawSize: CGSize) -> MTLTexture? {
        let width = Int(drawSize.width)
        let height = Int(drawSize.height)
        guard width > 0, height > 0 else { return nil }

        if let depthTexture,
           depthTexture.width == width,
           depthTexture.height == height {
            return depthTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let newTexture = metalDevice.makeTexture(descriptor: descriptor)
        newTexture?.label = RenderResourceName.depthTexture.rawValue
        depthTexture = newTexture
        return newTexture
    }

    func ensureBuildingWinnerIDTexture(drawSize: CGSize) -> MTLTexture? {
        let width = Int(drawSize.width)
        let height = Int(drawSize.height)
        guard width > 0, height > 0 else { return nil }

        if let buildingWinnerIDTexture,
           buildingWinnerIDTexture.width == width,
           buildingWinnerIDTexture.height == height {
            return buildingWinnerIDTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let newTexture = metalDevice.makeTexture(descriptor: descriptor)
        newTexture?.label = RenderResourceName.buildingWinnerIDTexture.rawValue
        buildingWinnerIDTexture = newTexture
        return newTexture
    }

    func ensureBuildingWinnerDepthTexture(drawSize: CGSize) -> MTLTexture? {
        let width = Int(drawSize.width)
        let height = Int(drawSize.height)
        guard width > 0, height > 0 else { return nil }

        if let buildingWinnerDepthTexture,
           buildingWinnerDepthTexture.width == width,
           buildingWinnerDepthTexture.height == height {
            return buildingWinnerDepthTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let newTexture = metalDevice.makeTexture(descriptor: descriptor)
        newTexture?.label = RenderResourceName.buildingWinnerDepthTexture.rawValue
        buildingWinnerDepthTexture = newTexture
        return newTexture
    }

    func reset() {
        depthTexture = nil
        buildingWinnerIDTexture = nil
        buildingWinnerDepthTexture = nil
    }
}
