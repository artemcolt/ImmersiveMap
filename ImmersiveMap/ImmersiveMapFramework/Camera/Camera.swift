//
//  Camera.swift
//  ImmersiveMap
//
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
    
    private class AABB {
        let minPoint: SIMD3<Float>
        let maxPoint: SIMD3<Float>
        
        init(minPoint: SIMD3<Float>, maxPoint: SIMD3<Float>) {
            self.minPoint = minPoint
            self.maxPoint = maxPoint
        }
    }
    
    private(set) var cameraMatrix: matrix_float4x4?
    
    init() {}
    
    var testPoints: [SIMD4<Float>] = []
    
    func recalculateProjection(aspect: Float) {
        self.projection = Matrix.perspectiveMatrix(fovRadians: Float.pi / 4, aspect: aspect, near: 0.001, far: 20.0)
        recalculateMatrix()
    }
    
    func recalculateMatrix() {
        view = Matrix.lookAt(eye: eye, center: center, up: up)
        cameraMatrix = projection! * view!
        
        frustrum = Frustum(pv: cameraMatrix!)
    }
    
    func aproximateTileGlobe(tx: Int, ty: Int, tz: Int, radius: Float,
                             rotation: float4x4,
                             pan: SIMD2<Float>) -> [SIMD4<Float>] {
        var step = Float(0.25)
        
        let count = Int(1.0 / step)
        var points: [SIMD4<Float>] = Array(repeating: SIMD4<Float>(), count: (count + 1) * (count + 1) )
        for x in 0...count {
            for y in 0...count {
                let point = getTileWorldPoint(tx: Float(tx) + Float(x) * step,
                                              ty: Float(ty) + Float(y) * step,
                                              tz: tz,
                                              radius: radius,
                                              rotation: rotation)
                points[x * (count + 1) + y] = point
            }
        }
        return points
    }
    
    func aproximateTileFlat(tx: Int, ty: Int, tz: Int, pan: SIMD2<Double>, radius: Double) -> [SIMD4<Float>] {
        let step = Double(1.0)
        
        let count = Int(1.0 / step)
        var points: [SIMD4<Float>] = Array(repeating: SIMD4<Float>(), count: (count + 1) * (count + 1) )
        for x in 0...count {
            for y in 0...count {
                let point = getTileFlatPoint(tx: Double(tx) + Double(x) * step,
                                             ty: Double(ty) + Double(y) * step,
                                             tz: tz,
                                             pan: pan,
                                             radius: radius)
                points[x * (count + 1) + y] = point
            }
        }
        return points
    }
    
    func boundingBox(for points: [SIMD4<Float>]) -> (min: SIMD4<Float>, max: SIMD4<Float>) {
        guard !points.isEmpty else {
            fatalError("Массив точек не может быть пустым")
        }
        
        // Инициализируем min и max первой точкой
        var minBounds = points[0]
        var maxBounds = points[0]
        
        // Проходим по остальным точкам и обновляем границы
        for point in points.dropFirst() {
            minBounds = simd_min(minBounds, point)
            maxBounds = simd_max(maxBounds, point)
        }
        
        return (min: minBounds, max: maxBounds)
    }
    
    func collectVisibleTilesGlobe(x: Int, y: Int, z: Int, targetZ: Int,
                                  radius: Float,
                                  rotation: float4x4,
                                  result: inout Set<Tile>,
                                  centerTile: Tile,
                                  mode: ViewMode,
                                  pan: SIMD2<Float>
    ) {
        let points = aproximateTileGlobe(tx: x, ty: y, tz: z, radius: radius, rotation: rotation, pan: pan)
        let boundingBox = boundingBox(for: points)
        //testPoints.append(boundingBox.min)
        //testPoints.append(boundingBox.max)
        let isVisibleBox = frustrum!.isBoxVisible(min: boundingBox.min, max: boundingBox.max)
        if isVisibleBox == false {
            return
        }
        
//        if z == 5 {
//            testPoints.append(contentsOf: points)
//        }
        
        var excludeByFaceDirection = false
        for point in points {
            let shiftPlanePoint = point.xyz + SIMD3<Float>(0, 0, radius)
            let pointNorm = normalize(shiftPlanePoint)
            let directionToCamera = normalize(eye)
            let dotProduct = dot(pointNorm, directionToCamera)
            excludeByFaceDirection = dotProduct <= -0.3
            
            if excludeByFaceDirection == false { break }
        }
        
        if excludeByFaceDirection {
            return
        }
        
        let zDiff = abs(centerTile.z - z)
        if zDiff == 0 {
            let addTile = Tile(x: x, y: y, z: z)
            let relX = abs(centerTile.x - x)
            let relY = abs(centerTile.y - y)
            let maxRelative = max(relX, relY)
            
            if maxRelative > 15 {
                // Тайл слишком далеко
                return
            }
            
            
            if maxRelative > 2 {
                // добавляем родителя, чтобы оптимизировать рендринг
                if let parent = addTile.findParentTile(atZoom: z - 1) {
                    result.insert(parent)
                    return
                }
            }
            
            result.insert(addTile)
            return
        }
        
        collectVisibleTilesGlobe(x: x * 2, y: y * 2, z: z + 1, targetZ: targetZ,
                                 radius: radius,
                                 rotation: rotation,
                                 result: &result,
                                 centerTile: centerTile,
                                 mode: mode,
                                 pan: pan)
        collectVisibleTilesGlobe(x: x * 2 + 1, y: y * 2, z: z + 1, targetZ: targetZ,
                                 radius: radius,
                                 rotation: rotation,
                                 result: &result,
                                 centerTile: centerTile,
                                 mode: mode,
                                 pan: pan)
        collectVisibleTilesGlobe(x: x * 2, y: y * 2 + 1, z: z + 1, targetZ: targetZ,
                                 radius: radius,
                                 rotation: rotation,
                                 result: &result,
                                 centerTile: centerTile,
                                 mode: mode,
                                 pan: pan)
        collectVisibleTilesGlobe(x: x * 2 + 1, y: y * 2 + 1, z: z + 1, targetZ: targetZ,
                                 radius: radius,
                                 rotation: rotation,
                                 result: &result,
                                 centerTile: centerTile,
                                 mode: mode,
                                 pan: pan)
    }
    
    func collectVisibleTilesFlat(x: Int, y: Int, z: Int, targetZ: Int,
                                 result: inout Set<Tile>,
                                 centerTile: Tile,
                                 pan: SIMD2<Double>,
                                 radius: Double
    ) {
        let points = aproximateTileFlat(tx: x, ty: y, tz: z, pan: pan, radius: radius)
        let boundingBox = boundingBox(for: points)
        //testPoints.append(boundingBox.min)
        //testPoints.append(boundingBox.max)
        let isVisibleBox = frustrum!.isBoxVisible(min: boundingBox.min, max: boundingBox.max)
        if isVisibleBox == false {
            return
        }
        
//        if z == 5 {
//            testPoints.append(contentsOf: points)
//        }
        
        let zDiff = abs(centerTile.z - z)
        if zDiff == 0 {
            let addTile = Tile(x: x, y: y, z: z)
            let relX = abs(centerTile.x - x)
            let relY = abs(centerTile.y - y)
            let maxRelative = max(relX, relY)
            
            if maxRelative > 15 {
                // Тайл слишком далеко
                return
            }
            
            
            if maxRelative > 2 {
                // добавляем родителя, чтобы оптимизировать рендринг
                if let parent = addTile.findParentTile(atZoom: z - 1) {
                    result.insert(parent)
                    return
                }
            }
            
            result.insert(addTile)
            return
        }
        
        collectVisibleTilesFlat(x: x * 2, y: y * 2, z: z + 1,
                                targetZ: targetZ,
                                result: &result,
                                centerTile: centerTile,
                                pan: pan,
                                radius: radius
        )
        collectVisibleTilesFlat(x: x * 2 + 1, y: y * 2, z: z + 1,
                                targetZ: targetZ,
                                result: &result,
                                centerTile: centerTile,
                                pan: pan,
                                radius: radius
        )
        collectVisibleTilesFlat(x: x * 2, y: y * 2 + 1, z: z + 1,
                                targetZ: targetZ,
                                result: &result,
                                centerTile: centerTile,
                                pan: pan,
                                radius: radius
        )
        collectVisibleTilesFlat(x: x * 2 + 1, y: y * 2 + 1, z: z + 1,
                                targetZ: targetZ,
                                result: &result,
                                centerTile: centerTile,
                                pan: pan,
                                radius: radius
        )
    }
    
    func createRotationMatrix(globe: Globe) -> float4x4 {
        let rotationPair = globe.getRotation()
        let xRotation = rotationPair.0
        let yRotation = rotationPair.1
        
        let distortion = cos(xRotation);
        print("distortion = \(distortion)")
        
        let cx = cos(-xRotation);
        let sx = sin(-xRotation);
        let cy = cos(-yRotation);
        let sy = sin(-yRotation);
        
        let rotation = float4x4(
            SIMD4<Float>(cy,        0,         -sy,       0),  // Колонка 0
            SIMD4<Float>(sy * sx,   cx,        cy * sx,   0),  // Колонка 1
            SIMD4<Float>(sy * cx,  -sx,        cy * cx,   0),  // Колонка 2
            SIMD4<Float>(0,         0,          0,        1)   // Колонка 3
        );
        
        return rotation
    }
    
    func getTileWorldPoint(tx: Float, ty: Float, tz: Int, radius: Float, rotation: float4x4) -> SIMD4<Float> {
        let latLon = getLatLon(tx: tx, ty: ty, tz: tz)
        let latitudeRad = latLon.latitude - Float.pi / 2.0
        let longitudeRad = latLon.longitude + Float.pi
        
        let phi = latitudeRad;
        let theta = longitudeRad;
        
        let x = radius * sin(phi) * sin(theta);
        let y = radius * cos(phi);
        let z = radius * sin(phi) * cos(theta);

        let point = SIMD4<Float>(x, y, z, 1)
        
        let transformedPoint = point * rotation - SIMD4<Float>(0, 0, radius, 0);
        return transformedPoint
    }

    private func getTileFlatPoint(tx: Double, ty: Double, tz: Int, pan: SIMD2<Double>, radius: Double) -> SIMD4<Float> {
        
        let mapSize = 2.0 * Double.pi * radius
        let halfMapSize = mapSize / 2.0
        let tilesCount = 1 << tz
        let tileSize = mapSize / Double(tilesCount)
        
        let x = tx * tileSize - halfMapSize + pan.x * halfMapSize
        let y = (Double(tilesCount) - ty) * tileSize - halfMapSize - pan.y * halfMapSize
        
        return SIMD4<Float>(Float(x), Float(y), 0, 1)
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

    private func wrap(_ x: Float, size: Float) -> Float {
        return x - size * floor((x + size * 0.5) / size)
    }

    private func getYMercNorm(latitude: Float) -> Float {
        let sinPan = sin(latitude)
        let maxSinPan = tanh(Float.pi)
        let clamped = max(-maxSinPan, min(maxSinPan, sinPan))
        let yMerc = 0.5 * log((1.0 + clamped) / (1.0 - clamped))
        return yMerc / Float.pi
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
}
