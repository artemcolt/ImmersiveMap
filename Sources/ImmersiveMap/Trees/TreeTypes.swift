//
//  TreeTypes.swift
//  ImmersiveMapFramework
//

import Foundation
import simd

enum TreeMaterialSlot: UInt32, CaseIterable {
    case trunk = 0
    case crown = 1
}

struct TreeInstanceInput {
    var uv: SIMD2<Float>
    var tile: SIMD3<Int32>
    var baseScale: Float
    var yawRadians: Float
    var featureKey: UInt64
}

struct TreeInstanceGPU {
    var uv: SIMD2<Float>
    var baseScale: Float
    var yawRadians: Float
}

struct TreeTileUniform {
    var origin: SIMD2<Float>
    var size: Float
    var runtimeScale: Float
    var yawFactor: Float
}

struct TreeMaterialUniform {
    var color: SIMD3<Float>
    var _padding0: Float = 0
}

struct TreeLightUniform {
    var direction: SIMD4<Float>
    var color: SIMD4<Float>
    var intensities: SIMD4<Float>
}
