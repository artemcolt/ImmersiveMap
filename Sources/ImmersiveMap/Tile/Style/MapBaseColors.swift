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
    
    init(settings: MapSettings.StyleSettings.BaseColors = MapSettings.default.style.baseColors) {
        self.tileBgColor = settings.tileBackground
        self.backgroundColor = settings.globeBackground
        self.waterColor = settings.water
        self.landCoverColor = settings.landCover
        self.northPoleColor = self.waterColor
        self.southPoleColor = self.landCoverColor
    }
}
