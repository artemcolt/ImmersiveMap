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
    private let maxLatitude = (2.0 * atan(exp(Double.pi)) - Double.pi / 2.0)
    
    func pan(deltaX: Double, deltaY: Double) {
        let yaw = Double(yaw)
        let startForward = SIMD2<Double>(0, 1)
        let sens = 0.05 / pow(2.0, Double(zoom))
        
        let cosYaw = cos(-yaw)
        let sinYaw = sin(-yaw)
        let forward = SIMD2<Double>(
            startForward.x * cosYaw - startForward.y * sinYaw,
            startForward.x * sinYaw + startForward.y * cosYaw
        )
        let right = -1 * SIMD2<Double>(
            -forward.y, forward.x
        )
        
        pan = pan + sens * (forward * deltaY + right * deltaX * 0.5)
        pan.y = min(max(-1, pan.y), 1)
        
        update = true
    }
    
    func setZoom(zoom: Float) {
        self.zoom = min(max(0, zoom), 20)
        update = true
    }
    
    func setLatLonDeg(latDeg: Double, lonDeg: Double) {
        pan.x = -(lonDeg / 180)
        
        let maxLatitudeDeg = maxLatitude * (180.0 / .pi)
        pan.y = (latDeg / maxLatitudeDeg)
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
        update = true
    }
}
