//
//  Globe.swift
//  ImmersiveMap
//
//  Created by Artem on 12/10/25.
//

import simd

struct Globe {
    let panX: Float
    let panY: Float
    let radius: Float
    let transition: Float
    
    func getRotation() -> (Float, Float) {
        let maxLatitude = 2.0 * atan(exp(Double.pi)) - (Double.pi / 2.0);
        let xRotation = Float(panY) * Float(maxLatitude)
        let yRotation = Float(panX) * Float.pi
        return (xRotation, yRotation)
    }
}
