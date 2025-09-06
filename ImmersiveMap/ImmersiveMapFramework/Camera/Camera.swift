//
//  Camera.swift
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

import MetalKit

class Camera {
    var projection: matrix_float4x4?
    var view: matrix_float4x4?
    
    var eye: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
    var center: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    
    private(set) var cameraMatrix: matrix_float4x4?
    
    func recalculateProjection(aspect: Float) {
        self.projection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4, aspect: aspect, near: 0.1, far: 10.0)
        recalculateMatrix()
    }
    
    func recalculateMatrix() {
        view = Matrix.lookAt(eye: eye, center: center, up: up)
        cameraMatrix = projection! * view!
    }
}
