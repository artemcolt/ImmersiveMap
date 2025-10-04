//
//  MapStyle.swift
//  TucikMap
//
//  Created by Artem on 8/24/25.
//

protocol MapStyle {
    func getMapBaseColors() -> MapBaseColors
    func filterTextLabels(properties: [String: Sendable], tile: Tile) -> FilterTextLabelsResult?
    func makeStyle(data: DetFeatureStyleData) -> FeatureStyle
}
