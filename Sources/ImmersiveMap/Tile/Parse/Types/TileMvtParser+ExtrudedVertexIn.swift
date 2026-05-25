//
//  TileMvtParser+ExtrudedVertexIn.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation
import simd

extension TileMvtParser {
    struct ExtrudedVertexIn {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let styleIndex: UInt8
        let _padding0: UInt8 = 0
        let _padding1: UInt8 = 0
        let _padding2: UInt8 = 0
        let surfaceID: UInt32
    }
}
