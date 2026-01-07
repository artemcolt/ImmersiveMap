//
//  CameraControl.swift
//  ImmersiveMap
//
//  Created by Artem on 9/5/25.
//

import simd

class CameraControl {
    var update: Bool = false
    
    var globePan: SIMD2<Double> = SIMD2<Double>(0, 0)
    var flatPan: SIMD2<Double> = SIMD2<Double>(0, 0)
    var yaw: Float = 0
    var pitch: Float = 0
    var zoom: Double = 0
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
        
        let speed = 0.5
        globePan = globePan + sens * (forward * deltaY * speed + right * deltaX * speed)
        globePan.y = min(max(-1, globePan.y), 1)
        globePan.x = wrapMinusOneToOne(globePan.x)
        
        flatPan = flatPan + sens * (forward * deltaY * speed + right * deltaX * speed)
        flatPan.y = min(max(-1, flatPan.y), 1)
        flatPan.x = wrapMinusOneToOne(flatPan.x)
        
        update = true
    }
    
    func setZoom(zoom: Double) {
        self.zoom = min(max(0, zoom), 20)
        update = true
    }
    
    func setLatLonDeg(latDeg: Double, lonDeg: Double) {
        // Для глобусного представления
        globePan.x = -(lonDeg / 180)
        
        let maxLatitudeDeg = maxLatitude * (180.0 / .pi)
        globePan.y = (latDeg / maxLatitudeDeg)
        
        // Для плоского представления
        flatPan.x = globePan.x
        
        let globeLat = (latDeg / 180.0) * Double.pi
        let yMerc = log(tan(Double.pi / 4.0 + globeLat / 2.0))
        let yNormalized = yMerc / Double.pi
        flatPan.y = yNormalized
    }
    
    func rotateYaw(delta: Float) {
        yaw += delta
        update = true
    }
    
    func rotatePitch(pitch: Float) {
        self.pitch = MapParameters.maxPitch - pitch
        update = true
    }
    
    func zoom(scale: Double) {
        let factor = Double(0.4)
        zoom += (scale - 1.0) * factor
        zoom = min(max(0, zoom), 20)
        update = true
    }
    
    private func wrapMinusOneToOne(_ x: Double) -> Double {
        let range = 2.0            // от -1 до +1
        var v = (x + 1.0).truncatingRemainder(dividingBy: range)
        if v < 0 { v += range }
        return v - 1.0
    }

}
