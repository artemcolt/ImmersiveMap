//
//  MapBaseColors.swift
//  TucikMap
//
//  Created by Artem on 8/24/25.
//

class MapBaseColors {
    fileprivate let tileBgColor: SIMD4<Float>
    fileprivate let backgroundColor: SIMD4<Double>
    fileprivate let waterColor: SIMD4<Float>
    fileprivate let landCoverColor: SIMD4<Float>
    fileprivate let northPoleColor: SIMD4<Float>
    fileprivate let southPoleColor: SIMD4<Float>
    
    public func getTileBgColor() -> SIMD4<Float> {
        return tileBgColor
    }
    
    public func getBackgroundColor() -> SIMD4<Double> {
        return backgroundColor
    }
    
    public func getWaterColor() -> SIMD4<Float> {
        return waterColor
    }
    
    public func getLandCoverColor() -> SIMD4<Float> {
        return landCoverColor
    }
    
    public func getNorthPoleColor() -> SIMD4<Float> {
        return northPoleColor
    }
    
    public func getSouthPoleColor() -> SIMD4<Float> {
        return southPoleColor
    }
    
    init(tileBgColor: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0),
         backgroundColor: SIMD4<Double> = SIMD4<Double>(0.0039, 0.0431, 0.0980, 1.0),
         waterColor: SIMD4<Float> = SIMD4<Float>(0.3, 0.6, 0.9, 1.0),
         landCoverColor: SIMD4<Float> = SIMD4<Float>(0.4, 0.7, 0.4, 0.7)) {
        
        self.tileBgColor = tileBgColor
        self.backgroundColor = backgroundColor
        self.waterColor = waterColor
        self.landCoverColor = landCoverColor
        
        self.northPoleColor = self.waterColor
        self.southPoleColor = self.landCoverColor
    }
}
