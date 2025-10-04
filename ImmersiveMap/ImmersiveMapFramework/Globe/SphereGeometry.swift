//
//  SphereGeometry.swift
//  ImmersiveMap
//
//  Created by Artem on 9/20/25.
//

import simd


class SphereGeometry {
    struct Vertex {
        var uv: SIMD2<Float>
    }

    var vertices: [Vertex] = []
    var indices: [UInt32] = []
    
    init(stacks: Int = 20, slices: Int = 20) {
        generate(stacks: stacks, slices: slices)
    }
    
    private func generate(stacks: Int, slices: Int) {
        vertices.removeAll()
        indices.removeAll()
        
        // Generate vertices and UVs
        for stack in 0...stacks {
            let v = Float(stack) / Float(stacks)
            for slice in 0...slices {
                let u = Float(slice) / Float(slices)
                let uv = SIMD2<Float>(u, v)
                vertices.append(Vertex(uv: uv))
            }
        }
        
        // Generate indices for triangles
        for stack in 0..<stacks {
            for slice in 0..<slices {
                let topLeft = stack * (slices + 1) + slice
                let topRight = topLeft + 1
                let bottomLeft = (stack + 1) * (slices + 1) + slice
                let bottomRight = bottomLeft + 1
                
                // First triangle
                indices.append(UInt32(topLeft))
                indices.append(UInt32(bottomLeft))
                indices.append(UInt32(topRight))
                
                // Second triangle
                indices.append(UInt32(topRight))
                indices.append(UInt32(bottomLeft))
                indices.append(UInt32(bottomRight))
            }
        }
    }
}
