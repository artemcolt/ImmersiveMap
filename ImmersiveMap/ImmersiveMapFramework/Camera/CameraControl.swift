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
    var zoom: Float = 0
    
    func pan(deltaX: Double, deltaY: Double) {
        let sens = 0.05 / pow(2.0, Double(zoom))
        pan.x += deltaX * sens / 2.0
        pan.y += deltaY * sens
        
        pan.y = min(max(-1, pan.y), 1)
        
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
    
    func zoom(scale: Float) {
        let factor = Float(0.4)
        zoom += (scale - 1.0) * factor
        zoom = min(max(0, zoom), 20)
        print("zoom = \(zoom)")
        update = true
    }
}
