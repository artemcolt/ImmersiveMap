//
//  Msaa.swift
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

import MetalKit

class Frame {
    private let metalDevice: MTLDevice
    private(set) var msaaTexture: MTLTexture?
    private var lastDrawableSize: CGSize = .zero
    private(set) var aspect: Float = 0
    
    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
    }
    
    func prepare(layer: CAMetalLayer, camera: Camera) {
        let currentDrawableSize = layer.drawableSize
        if currentDrawableSize != lastDrawableSize || msaaTexture == nil {
            lastDrawableSize = currentDrawableSize
            aspect = Float(lastDrawableSize.width) / Float(lastDrawableSize.height)
            
            camera.recalculateProjection(aspect: aspect)
            
            let msaaTextureDescriptor = MTLTextureDescriptor()
            msaaTextureDescriptor.textureType = .type2DMultisample
            msaaTextureDescriptor.pixelFormat = layer.pixelFormat
            msaaTextureDescriptor.width = Int(currentDrawableSize.width)
            msaaTextureDescriptor.height = Int(currentDrawableSize.height)
            msaaTextureDescriptor.storageMode = .private
            msaaTextureDescriptor.sampleCount = 4
            msaaTextureDescriptor.usage = .renderTarget
            
            // Проверяем на нулевой размер (чтобы избежать ошибок на старте)
            if currentDrawableSize.width > 0 && currentDrawableSize.height > 0 {
                msaaTexture = metalDevice.makeTexture(descriptor: msaaTextureDescriptor)
            } else {
                return // Пропускаем рендер, если размер нулевой
            }
        }
    }
}
