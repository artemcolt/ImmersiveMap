//
//  ViewModeCalculator.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Foundation

struct ViewModeResult {
    let transition: Float
    let radius: Double
    let mapSize: Double
    let globe: Globe
    let viewMode: ViewMode
}

struct ViewModeCalculator {
    static func calculate(zoom: Double, globePan: SIMD2<Double>) -> ViewModeResult {
        let worldScale = pow(2.0, floor(zoom))
        let from = Float(6.0)
        let span = Float(1.0)
        let to = from + span
        let transition = max(0.0, min(1.0, (Float(zoom) - from) / (to - from)))
        let radius = 0.14 * worldScale
        let mapSize = 2.0 * Double.pi * radius
        
        let globe = Globe(panX: Float(globePan.x),
                          panY: Float(globePan.y),
                          radius: Float(radius),
                          transition: transition)
        let viewMode: ViewMode = transition >= 1.0 ? .flat : .spherical
        return ViewModeResult(transition: transition,
                              radius: radius,
                              mapSize: mapSize,
                              globe: globe,
                              viewMode: viewMode)
    }
}
