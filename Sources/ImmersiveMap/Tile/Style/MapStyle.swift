//
//  MapStyle.swift
//  TucikMap
//
//  Created by Artem on 8/24/25.
//

protocol MapStyle {
    var preparedTileStyleRevision: UInt32 { get }
    func getMapBaseColors() -> MapBaseColors
    func makeStyle(data: DetFeatureStyleData) -> FeatureStyle
}
