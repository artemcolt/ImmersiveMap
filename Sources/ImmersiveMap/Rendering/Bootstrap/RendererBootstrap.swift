//
//  RendererBootstrap.swift
//  ImmersiveMapFramework
//  Created by Artem on 9/4/25.
//

import Metal
import MetalKit

enum RendererSetup {
    struct MetalContext {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        let library: MTLLibrary
    }

    static func buildMetal(layer: CAMetalLayer) -> MetalContext {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal не поддерживается на этом устройстве")
        }
        layer.device = metalDevice
        layer.pixelFormat = .bgra8Unorm
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("Не удалось создать command queue")
        }
        let bundle = Bundle.module
        let library = makeLibrary(metalDevice: metalDevice, bundle: bundle)
        return MetalContext(device: metalDevice, commandQueue: queue, library: library)
    }

    static func makeLibrary(metalDevice: MTLDevice, bundle: Bundle) -> MTLLibrary {
        do {
            return try metalDevice.makeDefaultLibrary(bundle: bundle)
        } catch {
            if let fallback = metalDevice.makeDefaultLibrary() {
                return fallback
            }
            fatalError("Не удалось создать MTLLibrary: \(error)")
        }
    }

    static func makeBaseGridBuffers(metalDevice: MTLDevice) -> GridBuffers {
        let baseGrid = SphereGeometry.createGrid(stacks: 50, slices: 50)
        return GridBuffers(
            verticesBuffer: metalDevice.makeBuffer(
                bytes: baseGrid.vertices,
                length: MemoryLayout<SphereGeometry.Vertex>.stride * baseGrid.vertices.count
            )!,
            indicesBuffer: metalDevice.makeBuffer(
                bytes: baseGrid.indices,
                length: MemoryLayout<UInt32>.stride * baseGrid.indices.count
            )!,
            indicesCount: baseGrid.indices.count
        )
    }

    static func configureCamera(_ cameraControl: CameraControl) {
        //cameraControl.setZoom(zoom: 8)
        cameraControl.setLatLonDeg(latDeg: 55.751244, lonDeg: 37.618423)
    }
}
