//
//  FeatureStyle.swift
//  TucikMap
//
//  Created by Artem on 5/29/25.
//

import MetalKit

class DetermineFeatureStyle {
    private let fallbackKey: UInt8 = 0
    private var fallbackStyle: FeatureStyle
    private let mapStyle: MapStyle

    init(mapStyle: MapStyle) {
        fallbackStyle = FeatureStyle(
            key: fallbackKey,
            color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0),
            parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 100)
        )
        
        self.mapStyle = mapStyle
    }
    
    func makeStyle(data: DetFeatureStyleData) -> FeatureStyle {
        return mapStyle.makeStyle(data: data)
    }
}
