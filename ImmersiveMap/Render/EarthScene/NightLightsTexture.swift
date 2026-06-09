// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import MetalKit

final class NightLightsTexture {
    private static let resourceName = "night_lights_black_marble_2016_gray"

    private let device: MTLDevice
    private let bundle: Bundle
    private let lock = NSLock()
    private var loadedTexture: MTLTexture?
    private let fallbackTexture: MTLTexture
    private var didAttemptLoad = false
    private var didReportLoadFailure = false
    private var _loadErrorDescription: String?

    var placeholderTexture: MTLTexture {
        fallbackTexture
    }

    private(set) var loadErrorDescription: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _loadErrorDescription
        }
        set {
            lock.lock()
            _loadErrorDescription = newValue
            lock.unlock()
        }
    }

    init(device: MTLDevice, bundle: Bundle = .module) {
        self.device = device
        self.bundle = bundle
        self.fallbackTexture = Self.makeFallbackTexture(device: device)
    }

    func texture() -> MTLTexture {
        lock.lock()
        defer { lock.unlock() }

        if let loadedTexture {
            return loadedTexture
        }
        guard didAttemptLoad == false else {
            return fallbackTexture
        }

        didAttemptLoad = true
        do {
            let texture = try loadBundledTexture()
            loadedTexture = texture
            return texture
        } catch {
            _loadErrorDescription = String(describing: error)
            if didReportLoadFailure == false {
                print("ImmersiveMap night lights texture unavailable: \(error)")
                didReportLoadFailure = true
            }
            return fallbackTexture
        }
    }

    private func loadBundledTexture() throws -> MTLTexture {
        guard let url = bundle.url(forResource: Self.resourceName, withExtension: "jpg")
            ?? bundle.url(forResource: Self.resourceName,
                          withExtension: "jpg",
                          subdirectory: "Render/EarthScene/Resources") else {
            throw LoadError.missingResource("\(Self.resourceName).jpg")
        }

        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(URL: url,
                                                options: [
                                                    .SRGB: false,
                                                    .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                                                    .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
                                                ])
            texture.label = "NightLightsTexture"
            return texture
        } catch {
            throw LoadError.decodeFailure(url, error)
        }
    }

    private static func makeFallbackTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                                                                 width: 1,
                                                                 height: 1,
                                                                 mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        let texture = device.makeTexture(descriptor: descriptor)!
        texture.label = "NightLightsTextureFallback"

        var pixel: UInt8 = 0
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1),
                        mipmapLevel: 0,
                        withBytes: &pixel,
                        bytesPerRow: 1)
        return texture
    }

    private enum LoadError: Error, CustomStringConvertible {
        case missingResource(String)
        case decodeFailure(URL, Error)

        var description: String {
            switch self {
            case .missingResource(let name):
                return "missing bundled resource \(name)"
            case .decodeFailure(let url, let error):
                return "failed to decode \(url.lastPathComponent): \(error)"
            }
        }
    }
}
