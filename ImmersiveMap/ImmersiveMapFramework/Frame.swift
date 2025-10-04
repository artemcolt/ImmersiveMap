//
//  Msaa.swift
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

import MetalKit

class Frame {
    struct Data {
        var msaaTexture: MTLTexture?
        var depthStencilTexture: MTLTexture?
        var lastDrawableSize: CGSize = .zero
    }
    
    private let metalDevice: MTLDevice
    
    private(set) var data: [Data] = Array(repeating: Data(msaaTexture: nil, depthStencilTexture: nil, lastDrawableSize: .zero), count: 3)
    private(set) var aspect: Float = 0
    
    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
    }
    
    func prepare(layer: CAMetalLayer, camera: Camera, index: Int) {
        let currentDrawableSize = layer.drawableSize
        let lastDrawableSize = data[index].lastDrawableSize
        let msaaTexture = data[index].msaaTexture
        
        if currentDrawableSize != lastDrawableSize || msaaTexture == nil {
            data[index].lastDrawableSize = currentDrawableSize
            aspect = Float(currentDrawableSize.width) / Float(currentDrawableSize.height)
            
            camera.recalculateProjection(aspect: aspect)
            
            let msaaTextureDescriptor = MTLTextureDescriptor()
            msaaTextureDescriptor.textureType = .type2DMultisample
            msaaTextureDescriptor.pixelFormat = layer.pixelFormat
            msaaTextureDescriptor.width = Int(currentDrawableSize.width)
            msaaTextureDescriptor.height = Int(currentDrawableSize.height)
            msaaTextureDescriptor.storageMode = .private
            msaaTextureDescriptor.sampleCount = 4
            msaaTextureDescriptor.usage = .renderTarget
            
            
            let depthStencilTextureDescriptor = MTLTextureDescriptor()
            depthStencilTextureDescriptor.textureType = .type2DMultisample
            depthStencilTextureDescriptor.sampleCount = 4
            depthStencilTextureDescriptor.pixelFormat = .depth32Float_stencil8
            depthStencilTextureDescriptor.width = Int(currentDrawableSize.width)
            depthStencilTextureDescriptor.height = Int(currentDrawableSize.height)
            depthStencilTextureDescriptor.storageMode = .private
            depthStencilTextureDescriptor.usage = [.renderTarget, .shaderRead]
            
            // Проверяем на нулевой размер (чтобы избежать ошибок на старте)
            if currentDrawableSize.width > 0 && currentDrawableSize.height > 0 {
                data[index].msaaTexture = metalDevice.makeTexture(descriptor: msaaTextureDescriptor)
                data[index].depthStencilTexture = metalDevice.makeTexture(descriptor: depthStencilTextureDescriptor)
            } else {
                return // Пропускаем рендер, если размер нулевой
            }
        }
    }
}
