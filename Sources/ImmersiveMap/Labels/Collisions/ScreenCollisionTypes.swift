//
//  ScreenCollisionTypes.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/6/26.
//

import simd

enum ScreenCollisionShapeType: UInt32 {
    case rect = 0
    case circle = 1
}

struct ScreenCollisionCandidate {
    var position: SIMD2<Float>
    var halfSize: SIMD2<Float>
    var priority: Int
    var secondaryPriority: Int
    var groupId: UInt64
    var isEnabled: Bool

    init(position: SIMD2<Float>,
         halfSize: SIMD2<Float>,
         priority: Int = .max,
         secondaryPriority: Int = .max,
         groupId: UInt64 = 0,
         isEnabled: Bool) {
        self.position = position
        self.halfSize = halfSize
        self.priority = priority
        self.secondaryPriority = secondaryPriority
        self.groupId = groupId
        self.isEnabled = isEnabled
    }
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
