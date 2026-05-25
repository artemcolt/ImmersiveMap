//
//  Camera.swift
//  ImmersiveMapFramework
//  Created by Artem on 9/4/25.
//

import MetalKit
import Metal

enum ViewMode {
    case spherical
    case flat
}

class Camera {
    var projection: matrix_float4x4?
    var view: matrix_float4x4?
    
    var eye: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
    var center: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    
    private(set) var frustrum: Frustum?
    
    private(set) var cameraMatrix: matrix_float4x4?
    
    init() {}
    
    func recalculateProjection(aspect: Float) {
        self.projection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4, aspect: aspect, near: 0.01, far: 20.0)
        recalculateMatrix()
    }
    
    func recalculateMatrix() {
        guard let projection else {
            assertionFailure("Camera projection must be set before recalculating matrices.")
            return
        }
        let view = Matrix.lookAt(eye: eye, center: center, up: up)
        self.view = view
        cameraMatrix = projection * view
        
        if let cameraMatrix {
            frustrum = Frustum(pv: cameraMatrix)
        } else {
            frustrum = nil
        }
    }
}

struct Frustum {
    var planes: [SIMD4<Float>]
    
    init(pv: matrix_float4x4) {
        // Extract planes using Gribb-Hartmann adjusted for Metal (0 to 1 depth buffer)
        // planes order: left, right, bottom, top, near, far
        let m0x = pv.columns.0.x  // array[0]
        let m0y = pv.columns.0.y  // array[1]
        let m0z = pv.columns.0.z  // array[2]
        let m0w = pv.columns.0.w  // array[3]
        let m1x = pv.columns.1.x  // array[4]
        let m1y = pv.columns.1.y  // array[5]
        let m1z = pv.columns.1.z  // array[6]
        let m1w = pv.columns.1.w  // array[7]
        let m2x = pv.columns.2.x  // array[8]
        let m2y = pv.columns.2.y  // array[9]
        let m2z = pv.columns.2.z  // array[10]
        let m2w = pv.columns.2.w  // array[11]
        let m3x = pv.columns.3.x  // array[12]
        let m3y = pv.columns.3.y  // array[13]
        let m3z = pv.columns.3.z  // array[14]
        let m3w = pv.columns.3.w  // array[15]
        
        var p: SIMD4<Float>
        
        // Left
        p = SIMD4<Float>(m0w + m0x, m1w + m1x, m2w + m2x, m3w + m3x)
        p /= length(SIMD3<Float>(p.x, p.y, p.z))
        planes = [p]
        
        // Right
        p = SIMD4<Float>(m0w - m0x, m1w - m1x, m2w - m2x, m3w - m3x)
        p /= length(SIMD3<Float>(p.x, p.y, p.z))
        planes.append(p)
        
        // Bottom
        p = SIMD4<Float>(m0w + m0y, m1w + m1y, m2w + m2y, m3w + m3y)
        p /= length(SIMD3<Float>(p.x, p.y, p.z))
        planes.append(p)
        
        // Top
        p = SIMD4<Float>(m0w - m0y, m1w - m1y, m2w - m2y, m3w - m3y)
        p /= length(SIMD3<Float>(p.x, p.y, p.z))
        planes.append(p)
        
        // Near (adjusted for Metal 0-1 depth)
        p = SIMD4<Float>(m0z, m1z, m2z, m3z)
        p /= length(SIMD3<Float>(p.x, p.y, p.z))
        planes.append(p)
        
        // Far
        p = SIMD4<Float>(m0w - m0z, m1w - m1z, m2w - m2z, m3w - m3z)
        p /= length(SIMD3<Float>(p.x, p.y, p.z))
        planes.append(p)
    }
    
    func isBoxVisible(min: SIMD4<Float>, max: SIMD4<Float>) -> Bool {
        for plane in planes {
            let px = plane.x >= 0 ? max.x : min.x
            let py = plane.y >= 0 ? max.y : min.y
            let pz = plane.z >= 0 ? max.z : min.z
            let dist = plane.x * px + plane.y * py + plane.z * pz + plane.w
            if dist < 0 {
                return false
            }
        }
        return true
    }

    func isSphereVisible(center: SIMD3<Float>,
                         radius: Float) -> Bool {
        for plane in planes {
            let distance = (plane.x * center.x) + (plane.y * center.y) + (plane.z * center.z) + plane.w
            if distance < -radius {
                return false
            }
        }
        return true
    }

    func containsSphere(center: SIMD3<Float>,
                        radius: Float) -> Bool {
        for plane in planes {
            let distance = (plane.x * center.x) + (plane.y * center.y) + (plane.z * center.z) + plane.w
            if distance < radius {
                return false
            }
        }
        return true
    }
}
