//
//  CapGeometry.swift
//  ImmersiveMap
//
//  Created by Artem on 1/10/26.
//

import simd

class CapGeometry {
    struct Vertex {
        var latLon: SIMD2<Float>
    }
    
    struct Grid {
        var vertices: [Vertex]
        var indices: [UInt32]
    }
    
    static func createCapGrid(stacks: Int, slices: Int, isNorth: Bool, maxLatitude: Float) -> Grid {
        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        
        let latStart: Float = isNorth ? maxLatitude : -Float.pi / 2.0
        let latEnd: Float = isNorth ? Float.pi / 2.0 : -maxLatitude
        
        for stack in 0...stacks {
            let t = Float(stack) / Float(stacks)
            let lat = latStart + (latEnd - latStart) * t
            for slice in 0...slices {
                let s = Float(slice) / Float(slices)
                let lon = s * Float.pi * 2.0
                vertices.append(Vertex(latLon: SIMD2<Float>(lat, lon)))
            }
        }
        
        for stack in 0..<stacks {
            for slice in 0..<slices {
                let topLeft = stack * (slices + 1) + slice
                let topRight = topLeft + 1
                let bottomLeft = (stack + 1) * (slices + 1) + slice
                let bottomRight = bottomLeft + 1
                
                indices.append(UInt32(topLeft))
                indices.append(UInt32(bottomLeft))
                indices.append(UInt32(topRight))
                
                indices.append(UInt32(topRight))
                indices.append(UInt32(bottomLeft))
                indices.append(UInt32(bottomRight))
            }
        }
        
        return Grid(vertices: vertices, indices: indices)
    }
}
