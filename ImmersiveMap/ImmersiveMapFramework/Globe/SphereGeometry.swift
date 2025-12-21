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
    
    struct Grid {
        var vertices: [Vertex]
        var indices: [UInt32]
    }

    var vertices: [Vertex] = []
    var indices: [UInt32] = []
    
    init(stacks: Int = 20, slices: Int = 20) {
        generate(stacks: stacks, slices: slices, tile: nil)
    }
    
    init(stacks: Int = 20, slices: Int = 20, tile: Tile) {
        generate(stacks: stacks, slices: slices, tile: tile)
    }
    
    func createGrid(stacks: Int, slices: Int) -> Grid {
        let uRange: (Float, Float) = (0.0, 1.0)
        let vRange: (Float, Float) = (0.0, 1.0)
        
        let uMin = uRange.0
        let uMax = uRange.1
        let vMin = vRange.0
        let vMax = vRange.1
        
        // Generate vertices and UVs
        for stack in 0...stacks {
            let t = Float(stack) / Float(stacks)
            let v = vMin + (vMax - vMin) * t
            for slice in 0...slices {
                let s = Float(slice) / Float(slices)
                let u = uMin + (uMax - uMin) * s
                vertices.append(Vertex(uv: SIMD2<Float>(u, v)))
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
    
    private func generate(stacks: Int, slices: Int, tile: Tile?) {
        vertices.removeAll()
        indices.removeAll()
        
        let uRange: (Float, Float)
        let vRange: (Float, Float)
        
        if let tile = tile {
            let n = Double(1 << tile.z)
            let uMin = Double(tile.x) / n
            let uMax = Double(tile.x + 1) / n
            
            let latNorth = atan(sinh(Double.pi * (1.0 - 2.0 * Double(tile.y) / n)))
            let latSouth = atan(sinh(Double.pi * (1.0 - 2.0 * Double(tile.y + 1) / n)))
            
            let vNorth = 1.0 - (latNorth + Double.pi / 2.0) / Double.pi
            let vSouth = 1.0 - (latSouth + Double.pi / 2.0) / Double.pi
            
            uRange = (Float(uMin), Float(uMax))
            vRange = (Float(vNorth), Float(vSouth))
        } else {
            uRange = (0.0, 1.0)
            vRange = (0.0, 1.0)
        }
        
        let uMin = uRange.0
        let uMax = uRange.1
        let vMin = vRange.0
        let vMax = vRange.1
        
        // Generate vertices and UVs
        for stack in 0...stacks {
            let t = Float(stack) / Float(stacks)
            let v = vMin + (vMax - vMin) * t
            for slice in 0...slices {
                let s = Float(slice) / Float(slices)
                let u = uMin + (uMax - uMin) * s
                vertices.append(Vertex(uv: SIMD2<Float>(u, v)))
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
