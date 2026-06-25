// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import ImmersiveMap

enum ExampleMapProvider {
    static func makeTileProvider() -> AnyImmersiveMapTileProvider {
        guard let tileBaseURLString = ProcessInfo.processInfo.environment["IMMERSIVE_MAP_TILE_BASE_URL"],
              let tileBaseURL = URL(string: tileBaseURLString) else {
            return AnyImmersiveMapTileProvider(OpenStreetMapTileProvider())
        }

        let source = ImmersiveMapTileSource
            .url(tileBaseURL)
            .token(ProcessInfo.processInfo.environment["IMMERSIVE_MAP_AUTH_TOKEN"])
        let provider = VectorTileProvider(
            id: "custom-mvt-host",
            cacheNamespace: "custom-mvt-host",
            tileSource: source,
            labelProfile: CustomHostedVectorTileLabelProfile.make(),
            maximumTileZoomLevel: 14
        )

        return AnyImmersiveMapTileProvider(provider)
    }

    static func makeMapStyle() -> AnyImmersiveMapMapStyle {
        guard ProcessInfo.processInfo.environment["IMMERSIVE_MAP_TILE_BASE_URL"] != nil else {
            return AnyImmersiveMapMapStyle(OpenStreetMapMapStyle())
        }

        return AnyImmersiveMapMapStyle(VectorTileMapStyle(style: CustomHostedVectorTileStyle()))
    }
}

private enum CustomHostedVectorTileLabelProfile {
    static func make() -> ImmersiveMapVectorTileLabelProfile {
        ImmersiveMapVectorTileLabelProfile(
            textKeys: ["title", "label", "name:en"],
            rankKeys: ["priority", "rank", "sort_rank"],
            kindKeys: ["category", "class", "type"],
            pointLabelLayers: ["place", "places", "place_labels", "poi", "pois"],
            houseNumberLayers: ["address", "address_label", "housenumber"],
            houseNumberTextKeys: ["number", "addr:housenumber"]
        )
    }
}

private struct CustomHostedVectorTileStyle: ImmersiveMapVectorTileStyle {
    private static let styleRevision: UInt32 = 1

    var cacheFingerprint: UInt32 {
        Self.styleRevision
    }

    var baseColors: ImmersiveMapSettings.StyleSettings.BaseColors? {
        ImmersiveMapSettings.StyleSettings.BaseColors(
            tileBackground: SIMD4<Float>(0.91, 0.90, 0.86, 1.0),
            globeBackground: SIMD4<Double>(0.91, 0.90, 0.86, 1.0),
            water: SIMD4<Float>(0.48, 0.66, 0.86, 1.0),
            landCover: SIMD4<Float>(0.74, 0.82, 0.66, 1.0)
        )
    }

    func makeStyle(for feature: ImmersiveMapFeatureStyleContext) -> ImmersiveMapFeatureStyle {
        switch feature.layerName {
        case "ocean", "water", "water_polygons":
            return .polygon(color: SIMD4<Float>(0.48, 0.66, 0.86, 1.0))
        case "landuse", "landcover", "land":
            return .polygon(color: SIMD4<Float>(0.74, 0.82, 0.66, 1.0))
        case "park", "parks":
            return .polygon(color: SIMD4<Float>(0.55, 0.74, 0.48, 1.0))
        case "building", "buildings":
            return .extrudedPolygon(color: SIMD4<Float>(0.72, 0.70, 0.66, 1.0),
                                    fallbackHeight: 12)
        case "transportation", "road", "roads":
            return .roadLabel(
                color: SIMD4<Float>(0.96, 0.94, 0.90, 1.0),
                width: 1.6,
                textStyle: ImmersiveMapLabelTextStyle(
                    fillColor: SIMD3<Float>(0.42, 0.41, 0.39),
                    strokeColor: SIMD3<Float>(1.0, 0.98, 0.92),
                    strokeWidthPx: 2,
                    sizePx: 11,
                    weight: .thin
                )
            )
        case "place", "places", "place_labels", "poi", "pois":
            return .pointLabel(
                ImmersiveMapLabelTextStyle(
                    fillColor: SIMD3<Float>(0.20, 0.20, 0.18),
                    strokeColor: SIMD3<Float>(1.0, 0.98, 0.92),
                    strokeWidthPx: 2,
                    sizePx: 14,
                    weight: .bold
                )
            )
        default:
            return .hidden
        }
    }
}
