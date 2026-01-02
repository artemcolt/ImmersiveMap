//
//  ScreenPoint.swift
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

class ScreenPoints {
    private var screenPoints: [SIMD2<Float>] = []
    
    func get() -> [SIMD2<Float>] {
        return screenPoints
    }
    
    func add(_ point: SIMD2<Float>) {
        screenPoints.append(point)
    }
    
    func update(_ point: SIMD2<Float>) {
        if screenPoints.count == 0 {
            screenPoints.append(point)
            return
        }
        screenPoints[0] = point
    }
}
