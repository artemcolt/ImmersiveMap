//
//  TileMvtParser+ParsedExtrudedMesh.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation

extension TileMvtParser {
    struct ParsedExtrudedVertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let surfaceID: UInt32
    }

    struct ParsedExtrudedMesh {
        var vertices: [ParsedExtrudedVertex]
        var indices: [UInt32]
    }
}
