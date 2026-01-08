//
//  ScreenCollisionTypes.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import simd

enum ScreenCollisionShapeType: UInt32 {
    case rect = 0
    case circle = 1
}

struct ScreenCollisionInput {
    var halfSize: SIMD2<Float>
    var radius: Float
    var shapeType: UInt32

    init(halfSize: SIMD2<Float>, radius: Float, shapeType: ScreenCollisionShapeType) {
        self.halfSize = halfSize
        self.radius = radius
        self.shapeType = shapeType.rawValue
    }
}
