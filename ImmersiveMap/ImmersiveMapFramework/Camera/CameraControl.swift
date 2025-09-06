//
//  CameraControl.swift
//  ImmersiveMap
//
//  Created by Artem on 9/5/25.
//

import simd

class CameraControl {
    var update: Bool = false
    
    var pan: SIMD2<Double> = SIMD2<Double>(0, 0)
    var yaw: Float = 0
    var pitch: Float = 0
    
    func pan(deltaX: Double, deltaY: Double) {
        pan.x += deltaX
        pan.y += deltaY
        update = true
    }
    
    func rotateYaw(delta: Float) {
        yaw += delta
        update = true
    }
    
    func rotatePitch(pitch: Float) {
        self.pitch = MapParameters.maxPitch - pitch
        update = true
    }
}
