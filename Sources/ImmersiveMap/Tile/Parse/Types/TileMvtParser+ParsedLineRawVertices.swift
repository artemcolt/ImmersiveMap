//
//  TileMvtParser+ParsedLineRawVertices.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation

extension TileMvtParser {
    struct ParsedLineRawVertices {
        let vertices: [SIMD3<Float>]
        let indices: [UInt32]
    }
}
