//
//  RendererAvatarDrawer.swift
//  ImmersiveMapFramework
//  Created by Artem on 3/10/26.
//

import Metal
import simd

final class RendererAvatarDrawer {
    private init() {}

    static func drawAvatars(renderEncoder: MTLRenderCommandEncoder,
                            screenMatrix: matrix_float4x4,
                            time: Float,
                            avatarsRenderer: AvatarsRenderer) {
        avatarsRenderer.drawAvatars(renderEncoder: renderEncoder,
                                    screenMatrix: screenMatrix,
                                    time: time)
    }
}
