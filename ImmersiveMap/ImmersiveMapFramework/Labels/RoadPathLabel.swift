//
//  RoadPathLabel.swift
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

struct RoadPathLabel {
    let text: String
    let key: UInt64
}

struct RoadPathRange {
    let start: Int
    let count: Int
    let labelIndex: Int
}

struct RoadPathRangeGpu {
    let start: UInt32
    let count: UInt32
    let _padding0: UInt32 = 0
    let _padding1: UInt32 = 0
}

struct RoadGlyphInput {
    let pathIndex: UInt32
    let instanceIndex: UInt32
    let labelInstanceIndex: UInt32
    let _padding: UInt32 = 0
    let glyphCenter: Float
    let labelWidth: Float
    let spacing: Float
    let minLength: Float
}

struct RoadGlyphPlacementOutput {
    let position: SIMD2<Float>
    let angle: Float
    let visible: UInt32
    let _padding: UInt32 = 0
}

struct RoadLabelGlyphRange {
    let start: UInt32
    let count: UInt32
    let _padding0: UInt32 = 0
    let _padding1: UInt32 = 0
}

struct RoadLabelAnchor {
    let pathIndex: UInt32
    let segmentIndex: UInt32
    let t: Float
    let _padding: Float = 0
}
