//
//  LabelRuntimeMeta.swift
//  ImmersiveMapFramework
//

struct LabelRuntimeMeta {
    var duplicate: UInt8
    var isRetained: UInt8
    var _padding: UInt16 = 0
    var visibleTileIndex: UInt32
    var fadeAlpha: Float = 0
    var _padding1: Float = 0
    var labelSizePx: SIMD2<Float> = .zero
}
