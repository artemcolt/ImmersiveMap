//
//  ScreenMatrix.swift
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

import Foundation
import simd

class ScreenMatrix {
    private var screenMatrix: matrix_float4x4?
    private var screenMatrixSize: CGSize = CGSize.zero
    
    func update(_ currentDrawableSize: CGSize) {
        if screenMatrixSize != currentDrawableSize {
            screenMatrixSize = currentDrawableSize
            screenMatrix = Matrix.orthographicMatrix(left: 0, right: Float(screenMatrixSize.width),
                                                     bottom: 0, top: Float(screenMatrixSize.height),
                                                     near: -1, far: 1)
        }
    }
    
    func get() -> matrix_float4x4? {
        return screenMatrix
    }
    
}
