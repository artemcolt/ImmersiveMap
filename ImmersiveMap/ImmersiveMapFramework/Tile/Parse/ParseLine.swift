//
//  ParseLine.swift
//  ImmersiveMap
//
//  Created by Artem on 1/1/26.
//

import Foundation
import simd

class ParseLine {
    func parse(line: LineString, width: Double, tileExtent: Float) -> [TileMvtParser.ParsedPolygon] {
        guard line.count >= 2, width > 0 else { return [] }
        
        let halfWidth = Float(width * 0.5)
        var polygons: [TileMvtParser.ParsedPolygon] = []
        
        for index in 0..<(line.count - 1) {
            let p0 = line[index]
            let p1 = line[index + 1]
            
            let start = SIMD2<Float>(Float(p0.x), tileExtent - Float(p0.y))
            let end = SIMD2<Float>(Float(p1.x), tileExtent - Float(p1.y))
            
            let delta = end - start
            let length = simd_length(delta)
            if length <= 0.0001 {
                continue
            }
            
            let normal = SIMD2<Float>(-delta.y / length, delta.x / length)
            let offset = normal * halfWidth
            
            let v0 = start + offset
            let v1 = start - offset
            let v2 = end + offset
            let v3 = end - offset
            
            let vertices: [SIMD2<Int16>] = [
                toShortVector(v0),
                toShortVector(v1),
                toShortVector(v2),
                toShortVector(v3)
            ]
            let indices: [UInt32] = [0, 2, 1, 1, 2, 3]
            
            polygons.append(TileMvtParser.ParsedPolygon(vertices: vertices, indices: indices))
        }
        
        return polygons
    }
    
    private func toShortVector(_ value: SIMD2<Float>) -> SIMD2<Int16> {
        let x = Int16(clamping: Int(value.x.rounded()))
        let y = Int16(clamping: Int(value.y.rounded()))
        return SIMD2<Int16>(x, y)
    }
}
