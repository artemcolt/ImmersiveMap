//
//  FeatureStyle.swift
//  TucikMap
//
//  Created by Artem on 5/29/25.
//

struct FeatureStyle {
    let key: UInt8
    let color: SIMD4<Float>
    let parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData
    let includeRoadLabelPath: Bool
    
    init(
        key: UInt8,
        color: SIMD4<Float>,
        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData,
        includeRoadLabelPath: Bool = false
    ) {
        self.key = key
        self.color = color
        self.parseGeometryStyleData = parseGeometryStyleData
        self.includeRoadLabelPath = includeRoadLabelPath
    }
}
