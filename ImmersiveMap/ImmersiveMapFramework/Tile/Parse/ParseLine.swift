//
//  ParseLine.swift
//  ImmersiveMap
//
//  Created by Artem on 1/1/26.
//

import Foundation
import simd

class ParseLine {
    func parse(line: LineString,
               width: Double,
               tileExtent: Float,
               lineCapRound: Bool,
               lineJoinRound: Bool) -> [TileMvtParser.ParsedPolygon] {
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
        
        if lineJoinRound, line.count > 2 {
            for index in 1..<(line.count - 1) {
                let prev = linePoint(at: index - 1, line: line, tileExtent: tileExtent)
                let center = linePoint(at: index, line: line, tileExtent: tileExtent)
                let next = linePoint(at: index + 1, line: line, tileExtent: tileExtent)
                
                let dir0 = normalizeSafe(center - prev)
                let dir1 = normalizeSafe(next - center)
                if simd_length(dir0) <= 0.0001 || simd_length(dir1) <= 0.0001 {
                    continue
                }
                
                let cross = dir0.x * dir1.y - dir0.y * dir1.x
                if abs(cross) <= 0.0001 {
                    continue
                }
                
                let left0 = SIMD2<Float>(-dir0.y, dir0.x)
                let left1 = SIMD2<Float>(-dir1.y, dir1.x)
                let innerIsLeft = cross < 0
                
                let inner0 = center + (innerIsLeft ? left0 : -left0) * halfWidth
                let inner1 = center + (innerIsLeft ? left1 : -left1) * halfWidth
                
                let vertices: [SIMD2<Int16>] = [
                    toShortVector(center),
                    toShortVector(inner0),
                    toShortVector(inner1)
                ]
                let indices: [UInt32] = [0, 1, 2]
                polygons.append(TileMvtParser.ParsedPolygon(vertices: vertices, indices: indices))
            }
        }
        
        if lineCapRound {
            if let startDir = capDirectionStart(line: line, tileExtent: tileExtent),
               let startCap = makeCap(center: linePoint(at: 0, line: line, tileExtent: tileExtent),
                                      direction: startDir,
                                      radius: halfWidth,
                                      flipDirection: true) {
                polygons.append(startCap)
            }
            if let endDir = capDirectionEnd(line: line, tileExtent: tileExtent),
               let endCap = makeCap(center: linePoint(at: line.count - 1, line: line, tileExtent: tileExtent),
                                    direction: endDir,
                                    radius: halfWidth,
                                    flipDirection: false) {
                polygons.append(endCap)
            }
        }
        
        return polygons
    }
    
    private func linePoint(at index: Int, line: LineString, tileExtent: Float) -> SIMD2<Float> {
        let point = line[index]
        return SIMD2<Float>(Float(point.x), tileExtent - Float(point.y))
    }
    
    private func lineDirection(startIndex: Int, line: LineString, tileExtent: Float) -> SIMD2<Float> {
        let start = linePoint(at: startIndex, line: line, tileExtent: tileExtent)
        let end = linePoint(at: startIndex + 1, line: line, tileExtent: tileExtent)
        let delta = end - start
        return normalizeSafe(delta)
    }

    private func capDirectionStart(line: LineString, tileExtent: Float) -> SIMD2<Float>? {
        if line.count < 2 {
            return nil
        }
        for i in 0..<(line.count - 1) {
            let dir = lineDirection(startIndex: i, line: line, tileExtent: tileExtent)
            if simd_length(dir) > 0.0001 {
                return dir
            }
        }
        return nil
    }

    private func capDirectionEnd(line: LineString, tileExtent: Float) -> SIMD2<Float>? {
        if line.count < 2 {
            return nil
        }
        for i in stride(from: line.count - 2, through: 0, by: -1) {
            let dir = lineDirection(startIndex: i, line: line, tileExtent: tileExtent)
            if simd_length(dir) > 0.0001 {
                return dir
            }
        }
        return nil
    }
    
    private func normalizeSafe(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(value)
        if length <= 0.0001 {
            return SIMD2<Float>(0, 0)
        }
        return value / length
    }
    
    private func makeCap(center: SIMD2<Float>,
                         direction: SIMD2<Float>,
                         radius: Float,
                         flipDirection: Bool) -> TileMvtParser.ParsedPolygon? {
        let length = simd_length(direction)
        if length <= 0.0001 {
            return nil
        }
        
        let forward = flipDirection ? -direction : direction
        let right = SIMD2<Float>(-forward.y, forward.x)
        let segments = 8
        
        var vertices: [SIMD2<Int16>] = [toShortVector(center)]
        vertices.reserveCapacity(segments + 2)
        
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let angle = (-0.5 + t) * Float.pi
            let point = center + (forward * cos(angle) + right * sin(angle)) * radius
            vertices.append(toShortVector(point))
        }
        
        var indices: [UInt32] = []
        indices.reserveCapacity(segments * 3)
        for i in 1..<(segments + 1) {
            indices.append(0)
            indices.append(UInt32(i))
            indices.append(UInt32(i + 1))
        }
        
        return TileMvtParser.ParsedPolygon(vertices: vertices, indices: indices)
    }
    
    
    private func toShortVector(_ value: SIMD2<Float>) -> SIMD2<Int16> {
        let x = Int16(clamping: Int(value.x.rounded()))
        let y = Int16(clamping: Int(value.y.rounded()))
        return SIMD2<Int16>(x, y)
    }
}
