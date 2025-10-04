//
//  Camera.swift
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

import MetalKit

class Camera {
    var projection: matrix_float4x4?
    var view: matrix_float4x4?
    
    var eye: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
    var center: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    
    private(set) var cameraMatrix: matrix_float4x4?
    
    var testPoints: [SIMD4<Float>] = []
    
    func recalculateProjection(aspect: Float) {
        self.projection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4, aspect: aspect, near: 0.01, far: 10.0)
        recalculateMatrix()
    }
    
    func recalculateMatrix() {
        view = Matrix.lookAt(eye: eye, center: center, up: up)
        cameraMatrix = projection! * view!
    }
    
    
    func collectVisibleTiles(tx: Int, ty: Int, tz: Int, frustum: Frustum, globe: Renderer.Globe, targetZoom: Int, result: inout [Tile]) {
        // Base case: if current zoom exceeds target, stop recursion
        guard tz <= targetZoom else { return }
        
        // Check if this tile intersects the frustum
        let isVisible = intersects(tx: tx, ty: ty, tz: tz, frustum: frustum, globe: globe)
        
        if isVisible {
            if tz == targetZoom {
                // At target zoom, add the tile to the result
                let tile = Tile(x: Int(tx), y: Int(ty), z: tz) // Adjust Tile init as per your struct
                result.append(tile)
            } else {
                // Recurse into children (quad-tree division)
                let nextZ = tz + 1
                let nextTxBase = tx * 2
                let nextTyBase = ty * 2
                
                // Child 0: (2x, 2y)
                collectVisibleTiles(tx: nextTxBase, ty: nextTyBase, tz: nextZ, frustum: frustum, globe: globe, targetZoom: targetZoom, result: &result)
                
                // Child 1: (2x + 1, 2y)
                collectVisibleTiles(tx: nextTxBase + 1, ty: nextTyBase, tz: nextZ, frustum: frustum, globe: globe, targetZoom: targetZoom, result: &result)
                
                // Child 2: (2x, 2y + 1)
                collectVisibleTiles(tx: nextTxBase, ty: nextTyBase + 1, tz: nextZ, frustum: frustum, globe: globe, targetZoom: targetZoom, result: &result)
                
                // Child 3: (2x + 1, 2y + 1)
                collectVisibleTiles(tx: nextTxBase + 1, ty: nextTyBase + 1, tz: nextZ, frustum: frustum, globe: globe, targetZoom: targetZoom, result: &result)
            }
        }
    }
    
    private func intersects(tx: Int, ty: Int, tz: Int, frustum: Frustum, globe: Renderer.Globe) -> Bool {
        let wp1: SIMD4<Float> = getTileWorldPoint(tx: Float(tx), ty: Float(ty), tz: tz, globe: globe)
        let wp2: SIMD4<Float> = getTileWorldPoint(tx: Float(tx) + 1.0, ty: Float(ty), tz: tz, globe: globe)
        let wp3: SIMD4<Float> = getTileWorldPoint(tx: Float(tx), ty: Float(ty) + 1.0, tz: tz, globe: globe)
        let wp4: SIMD4<Float> = getTileWorldPoint(tx: Float(tx) + 1.0, ty: Float(ty) + 1.0, tz: tz, globe: globe)
        
        let minX = min(wp1.x, wp2.x, wp3.x, wp4.x)
        let minY = min(wp1.y, wp2.y, wp3.y, wp4.y)
        let minZ = min(wp1.z, wp2.z, wp3.z, wp4.z)

        let maxX = max(wp1.x, wp2.x, wp3.x, wp4.x)
        let maxY = max(wp1.y, wp2.y, wp3.y, wp4.y)
        let maxZ = max(wp1.z, wp2.z, wp3.z, wp4.z)
        
        let minPoint = SIMD4<Float>(minX, minY, minZ, 1.0)
        let maxPoint = SIMD4<Float>(maxX, maxY, maxZ, 1.0)
        
        //testPoints.append(tileCenter)
        
        func getTileNVector(vec: SIMD4<Float>) -> SIMD3<Float> {
            return normalize(SIMD3<Float>(vec.x, vec.y, vec.z + globe.radius))
        }
        
        let cameraDir4 = center - eye
        let cameraDir: SIMD3<Float> = normalize(SIMD3<Float>(cameraDir4.x, cameraDir4.y, cameraDir4.z))
        
        
        let dotProduct1 = dot(getTileNVector(vec: wp1), cameraDir)
        let dotProduct2 = dot(getTileNVector(vec: wp2), cameraDir)
        let dotProduct3 = dot(getTileNVector(vec: wp3), cameraDir)
        let dotProduct4 = dot(getTileNVector(vec: wp4), cameraDir)
        
        if dotProduct1 > 0 && dotProduct2 > 0 && dotProduct3 > 0 && dotProduct4 > 0 && tz > 0 {
            return false
        }
        //testPoints.append(contentsOf: [wp1, wp2, wp3, wp4])
        
        return frustum.intersects(aabbMin: minPoint, aabbMax: maxPoint)
    }
    
    func getTileWorldPoint(tx: Float, ty: Float, tz: Int, globe: Renderer.Globe) -> SIMD4<Float> {
        let latLon = getLatLon(tx: tx, ty: ty, tz: tz)
        let latitudeRad = latLon.latitude
        let longitudeRad = latLon.longitude
        let radius = globe.radius
        
        let xRotation = globe.xRotation
        let yRotation = globe.yRotation
        
        let cosLat = cos(latitudeRad)
        let sinLat = sin(latitudeRad)
        let cosLon = cos(-longitudeRad)
        let sinLon = sin(-longitudeRad)

        let worldPosition = SIMD3<Float>(
            x: radius * cosLat * cosLon,
            y: radius * sinLat,
            z: radius * cosLat * sinLon
        )
        let wp = Matrix.translationMatrix(x: 0, y: 0, z: -globe.radius) *
                 Matrix.rotationMatrixX(xRotation) *
                 Matrix.rotationMatrixY(yRotation - Float.pi / 2) * SIMD4<Float>(worldPosition.x, worldPosition.y, worldPosition.z, 1.0)
        
        return wp
    }
    
    private func getLatLon(tx: Float, ty: Float, tz: Int) -> (latitude: Float, longitude: Float) {
        let n: Int = 1 << tz
        let txDouble: Float = Float(tx)
        let nDouble: Float = Float(n)
        let fractionX: Float = txDouble / nDouble
        let longitudeRad: Float = fractionX * 2.0 * .pi - .pi
        let fractionY: Float = Float(ty) / nDouble
        let temp: Float = 1.0 - 2.0 * fractionY
        let sinhArg: Float = .pi * temp
        let sinhVal: Float = sinh(sinhArg)
        let latitudeRad: Float = atan(sinhVal)
        return (latitudeRad, longitudeRad)
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
    
    // New: Test if AABB intersects frustum (potentially visible)
    func intersects(aabbMin: SIMD4<Float>, aabbMax: SIMD4<Float>) -> Bool {
        for plane in planes {
            let px = plane.x >= 0 ? aabbMax.x : aabbMin.x
            let py = plane.y >= 0 ? aabbMax.y : aabbMin.y
            let pz = plane.z >= 0 ? aabbMax.z : aabbMin.z
            let maxDist = plane.x * px + plane.y * py + plane.z * pz + plane.w
            if maxDist < 0 {
                return false
            }
        }
        return true
    }
}
