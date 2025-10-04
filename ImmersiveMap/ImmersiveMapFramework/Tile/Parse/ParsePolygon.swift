//
//  ParsePolygon.swift
//  TucikMap
//
//  Created by Artem on 5/29/25.
//

import MetalKit
internal import SwiftEarcut

class ParsePolygon {
    private let clipper = Clipper()
    
    func parse(polygon: Polygon, tileExtent: Float) -> TileMvtParser.ParsedPolygon? {
        
        let clipPoly = Clipper.Polygon(points: [
            Clipper.Point(x: 0.0, y: 0.0),
            Clipper.Point(x: 4096.0, y: 0.0),
            Clipper.Point(x: 4096.0, y: 4096.0),
            Clipper.Point(x: 0.0, y: 4096.0)
        ])
        
        let p1 = polygon.exteriorRing.map { point in Clipper.Point(x: Double(point.x), y: 4096.0 - Double(point.y)) }
        guard let exteriorClipped = clipper.sutherlandHodgmanClip(subjPoly: Clipper.Polygon(points: p1), clipPoly: clipPoly) else { return nil }
        
        var interiorClipped: [Clipper.Polygon] = []
        for ring in polygon.interiorRings {
            let p2 = ring.map { point in Clipper.Point(x: Double(point.x), y: 4096.0 - Double(point.y)) }
            if let polygon = clipper.sutherlandHodgmanClip(subjPoly: Clipper.Polygon(points: p2), clipPoly: clipPoly) {
                interiorClipped.append(polygon)
            }
        }
        
        
        var holeIndices: [Int] = []
        var points: [Double] = []
        for point in exteriorClipped.points {
            points.append(contentsOf: [Double(point.x), Double(point.y)])
        }
        for ring in interiorClipped {
            holeIndices.append(points.count / 2)
            for point in ring.points {
                points.append(contentsOf: [Double(point.x), Double(point.y)])
            }
        }
        
        let indices = Earcut.tessellate(data: points, holeIndices: holeIndices, dim: 2).map { UInt32($0) }
        
        var vertices: [SIMD2<Int16>] = []
        for i in stride(from: 0, to: points.count, by: 2) {
            let x: Int16 = Int16(points[i])
            let y: Int16 = Int16(points[i+1])
            vertices.append(SIMD2<Int16>(x, y))
        }
        
        if indices.isEmpty { return nil}
        
        return TileMvtParser.ParsedPolygon(
            vertices: vertices,
            indices: indices
        )
    }
}
