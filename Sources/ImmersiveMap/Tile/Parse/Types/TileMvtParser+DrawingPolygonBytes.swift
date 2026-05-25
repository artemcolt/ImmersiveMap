//
//  TileMvtParser+DrawingPolygonBytes.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation

extension TileMvtParser {
    struct DrawingPolygonBytes {
        var vertices: [TilePipeline.VertexIn]
        var indices: [UInt32]
    }
}
