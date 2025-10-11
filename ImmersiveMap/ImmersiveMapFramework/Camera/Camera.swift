//
//  Camera.swift
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

import MetalKit
import Metal

class Camera {
    var projection: matrix_float4x4?
    var view: matrix_float4x4?
    
    var eye: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
    var center: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    
    private class AABB {
        let minPoint: SIMD3<Float>
        let maxPoint: SIMD3<Float>
        
        init(minPoint: SIMD3<Float>, maxPoint: SIMD3<Float>) {
            self.minPoint = minPoint
            self.maxPoint = maxPoint
        }
    }
    
    private(set) var cameraMatrix: matrix_float4x4?
    
    init() {
    }
    
    var testPoints: [SIMD4<Float>] = []
    
    func recalculateProjection(aspect: Float) {
        self.projection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4, aspect: aspect, near: 0.001, far: 30.0)
        recalculateMatrix()
    }
    
    func recalculateMatrix() {
        view = Matrix.lookAt(eye: eye, center: center, up: up)
        cameraMatrix = projection! * view!
    }
    
    func aproximateTile(tx: Int, ty: Int, tz: Int, globe: Renderer.Globe, step: Float) -> [SIMD4<Float>] {
        let count = Int(1.0 / step)
        var points: [SIMD4<Float>] = Array(repeating: SIMD4<Float>(), count: (count + 1) * (count + 1) )
        for x in 0...count {
            for y in 0...count {
                points[x * (count + 1) + y] = getTileWorldPoint(tx: Float(tx) + Float(x) * step, ty: Float(ty) + Float(y) * step, tz: tz, globe: globe)
            }
        }
        return points
    }
    
    func collectVisibleTiles(x: Int, y: Int, z: Int, targetZ: Int,
                             globe: Renderer.Globe,
                             frustrum: Frustum,
                             result: inout [Tile],
                             centerTile: Tile
    ) {
        var step = Float(0.25)
        if z > 3 {
            step = 0.5
        }
        
        let points = aproximateTile(tx: x, ty: y, tz: z, globe: globe, step: step)
        
        var maxX: Float = points[0].x
        var maxY: Float = points[0].y
        var maxZ: Float = points[0].z
        
        var minX: Float = points[0].x
        var minY: Float = points[0].y
        var minZ: Float = points[0].z
        
        let cameraDirection = normalize(center - eye)
        var faced = false
        for point in points {
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
            maxZ = max(maxZ, point.z)
            
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            minZ = min(minZ, point.z)
            
            if faced == false {
                let normal = normalize(point.xyz + SIMD3<Float>(0, 0, globe.radius))
                if dot(normal, cameraDirection) < 0.1 {
                    faced = true
                }
            }
        }
        
        if faced == false {
            return
        }
        
        let minPoint = SIMD3<Float>(minX, minY, minZ)
        let maxPoint = SIMD3<Float>(maxX, maxY, maxZ)
        
        let contains = frustrum.intersectsAABB(minPoint: minPoint, maxPoint: maxPoint)
        
//        if z == targetZ {
//            testPoints.append(contentsOf: points)
//        }
        
        if contains == false {
            return
        }
        
        let zDiff = abs(centerTile.z - z)
        let diff = 1 << zDiff
        let relCenterX = Int(centerTile.x / diff)
        let relCenterY = Int(centerTile.y / diff)
        
        let dx = abs(x - relCenterX)
        let dy = abs(y - relCenterY)
        let maxD = max(dx, dy)
        
        if zDiff > 0 && maxD > 1 {
            result.append(Tile(x: x, y: y, z: z))
            return
        }
        
        if zDiff == 0 {
            result.append(Tile(x: x, y: y, z: z))
            return
        }
        
        collectVisibleTiles(x: x * 2, y: y * 2, z: z + 1, targetZ: targetZ, globe: globe, frustrum: frustrum, result: &result, centerTile: centerTile)
        collectVisibleTiles(x: x * 2 + 1, y: y * 2, z: z + 1, targetZ: targetZ, globe: globe, frustrum: frustrum, result: &result, centerTile: centerTile)
        collectVisibleTiles(x: x * 2, y: y * 2 + 1, z: z + 1, targetZ: targetZ, globe: globe, frustrum: frustrum, result: &result, centerTile: centerTile)
        collectVisibleTiles(x: x * 2 + 1, y: y * 2 + 1, z: z + 1, targetZ: targetZ, globe: globe, frustrum: frustrum, result: &result, centerTile: centerTile)
    }
    
    func getTileWorldPoint(tx: Float, ty: Float, tz: Int, globe: Renderer.Globe) -> SIMD4<Float> {
        let latLon = getLatLon(tx: tx, ty: ty, tz: tz)
        let latitudeRad = latLon.latitude
        let longitudeRad = latLon.longitude
        let radius = globe.radius
        
        let xRotation = globe.xRotation
        let yRotation = globe.yRotation
        
        let theta = yRotation - Float.pi / 2
        let cosTheta = cos(theta)
        let sinTheta = sin(theta)
        let cosPhi = cos(xRotation)
        let sinPhi = sin(xRotation)

        let cosLat = cos(latitudeRad)
        let sinLat = sin(latitudeRad)
        let cosLon = cos(-longitudeRad)
        let sinLon = sin(-longitudeRad)

        let x = radius * cosLat * cosLon
        let y = radius * sinLat
        let z = radius * cosLat * sinLon

        let xp = cosTheta * x + sinTheta * z
        let yp = cosPhi * y + sinPhi * (sinTheta * x - cosTheta * z)
        let zp = sinPhi * y - cosPhi * sinTheta * x + cosPhi * cosTheta * z

        let wp = SIMD4<Float>(xp, yp, zp - radius, 1.0)
        
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
    
    func containsAny(points: [SIMD4<Float>]) -> Bool {
        for point in points {
            var isInside = true
            for plane in planes {
                let distance = dot(plane, point)
                if distance < 0 {
                    isInside = false
                    break
                }
            }
            if isInside {
                return true
            }
        }
        return false
    }
    
    func intersectsAABB(minPoint: SIMD3<Float>, maxPoint: SIMD3<Float>) -> Bool {
            let corners: [SIMD4<Float>] = [
                SIMD4<Float>(minPoint.x, minPoint.y, minPoint.z, 1.0),
                SIMD4<Float>(minPoint.x, minPoint.y, maxPoint.z, 1.0),
                SIMD4<Float>(minPoint.x, maxPoint.y, minPoint.z, 1.0),
                SIMD4<Float>(minPoint.x, maxPoint.y, maxPoint.z, 1.0),
                SIMD4<Float>(maxPoint.x, minPoint.y, minPoint.z, 1.0),
                SIMD4<Float>(maxPoint.x, minPoint.y, maxPoint.z, 1.0),
                SIMD4<Float>(maxPoint.x, maxPoint.y, minPoint.z, 1.0),
                SIMD4<Float>(maxPoint.x, maxPoint.y, maxPoint.z, 1.0)
            ]
            
            for plane in planes {
                var allOutside = true
                for corner in corners {
                    let distance = dot(plane, corner)
                    if distance >= 0 {
                        allOutside = false
                        break
                    }
                }
                if allOutside {
                    return false // Completely outside this plane
                }
            }
            return true // Intersects or is inside the frustum
        }
}
