//
//  TileMvtParser+DrawingExtrudedBytes.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation

extension TileMvtParser {
    struct DrawingExtrudedBytes {
        var vertices: [ExtrudedVertexIn]
        var indices: [UInt32]
        var styles: [TilePolygonStyle]
    }
}
