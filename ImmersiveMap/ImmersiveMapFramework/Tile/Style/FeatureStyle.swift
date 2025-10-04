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
}
