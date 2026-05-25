//
//  TileMvtParser+ParsedPolygon.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation

extension TileMvtParser {
    struct ParsedPolygon {
        var vertices: [SIMD2<Int16>] = []
        var indices: [UInt32] = []
    }
}
