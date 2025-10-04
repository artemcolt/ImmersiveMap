//
//  DefaultMapStyle.swift
//  TucikMap
//
//  Created by Artem on 8/24/25.
//

import MetalKit


class DefaultMapStyle: MapStyle {
    private let fallbackKey: UInt8 = 0
    private let fallbackStyle: FeatureStyle
    private let mapBaseColors: MapBaseColors = MapBaseColors()
    
    private var getOnlySpecificMapLabels: [String] = []
    
    
    init() {
        fallbackStyle = FeatureStyle(
            key: fallbackKey,
            color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0),
            parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 100)
        )
    }
    
    func getMapBaseColors() -> MapBaseColors {
        return mapBaseColors
    }
    
    func filterTextLabels(properties: [String: Sendable], tile: Tile) -> FilterTextLabelsResult? {
        guard let nameEn = properties["name_en"] as? String else {return nil}
        if getOnlySpecificMapLabels.isEmpty == false {
            if getOnlySpecificMapLabels.contains(nameEn) == false {
                return nil
            }
        }
        
        let filterRank = ushort(properties["filterrank"] as? UInt64 ?? 100)
        _ = ushort(properties["sizerank"] as? UInt64 ?? 15)
        let symbolRank = ushort(properties["symbolrank"] as? UInt64 ?? 20)
        guard let _class = properties["class"] as? String else { return nil }
        let type = properties["type"] as? String ?? ""
        let capital = properties["capital"] as? UInt64 ?? 0
        
        //print("type = \(type), class = \(_class), filterRank = \(filterRank), sizeRank = \(sizeRank), symbolRank = \(symbolRank), \(nameEn), ")
        //print("props = \(properties), \(nameEn)")
        
        var scale: Float = 50;
        if capital == 2 {
            scale = 70
        } else  if capital == 1 {
            scale = 60
        }
        if _class == "continent" {
            scale = 70
        }
        
        if(tile.z <= 2) {
            if (["country", "continent"].contains(_class)) {
                return FilterTextLabelsResult(text: nameEn, scale: scale, sortRank: symbolRank)
            }
        } else if (tile.z <= 3) {
            if (["city"].contains(type) && filterRank <= 5) {
                return FilterTextLabelsResult(text: nameEn, scale: scale, sortRank: symbolRank)
            }
        } else if (tile.z <= 12) {
            return FilterTextLabelsResult(text: nameEn, scale: scale, sortRank: symbolRank)
        } else if (tile.z <= 15) {
            if (["suburb", "town", "hamlet", "neighbourhood"].contains(type) && filterRank <= 5) {
                return FilterTextLabelsResult(text: nameEn, scale: scale, sortRank: symbolRank)
            }
        }
        
        return nil
    }
    
    func makeStyle(data: DetFeatureStyleData) -> FeatureStyle {
        let tile = data.tile
        let properties = data.properties
        let classValue = properties["class"]?.stringValue

        // Color palette (RGBA, normalized to 0.0-1.0)
        let colors = [
            "admin_boundary": SIMD4<Float>(0.65, 0.65, 0.75, 1.0), // Soft purple-gray
            "admin_level_1": SIMD4<Float>(0.45, 0.55, 0.85, 1.0), // Deeper blue
            "water": mapBaseColors.getWaterColor(),
            "river": SIMD4<Float>(0.2, 0.5, 0.8, 1.0),           // Slightly darker blue
            "landcover_forest": SIMD4<Float>(0.2, 0.6, 0.4, 0.7), // Forest green
            "landcover_grass": mapBaseColors.getLandCoverColor(),
            "road_major": SIMD4<Float>(0.9, 0.9, 0.9, 1.0),       // Near-white
            "road_minor": SIMD4<Float>(0.7, 0.7, 0.7, 1.0),       // Light gray
            "fallback": SIMD4<Float>(0.5, 0.5, 0.5, 0.5),          // Neutral gray
            "background": mapBaseColors.getTileBgColor(),
            "border": SIMD4<Float>(0.0, 0.0, 0.0, 1.0),
            
            "building": SIMD4<Float>(0.8, 0.7, 0.6, 0.8),         // Warm beige
        ]
        
        switch data.layerName {
        case "background":
            return FeatureStyle(
                key: 1,
                color: colors["background"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )
        case "landcover":
            if classValue == "forest" {
                return FeatureStyle(
                    key: 11, // Bottom layer, above fallback
                    color: colors["landcover_forest"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            } else if classValue == "grass" {
                return FeatureStyle(
                    key: 12, // Above forest
                    color: colors["landcover_grass"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }
            return FeatureStyle(
                key: 10,
                color: colors["landcover_grass"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )

        case "water":
            if classValue == "river" {
                return FeatureStyle(
                    key: 21, // Above general water
                    color: colors["river"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 3) // Thin line for rivers
                )
            }
            return FeatureStyle(
                key: 20, // Above landcover
                color: colors["water"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0) // Filled polygon
            )

//        case "admin":
//            if let adminLevel = properties["admin_level"] as? UInt64 {
//                if adminLevel == 1 {
//                    return FeatureStyle(
//                        key: 102, // Above water
//                        color: colors["admin_level_1"]!,
//                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 8)
//                    )
//                } else if adminLevel == 2 {
//                    return FeatureStyle(
//                        key: 101,
//                        color: colors["admin_boundary"]!,
//                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 5)
//                    )
//                }
//            }
//            return FeatureStyle(
//                key: 100,
//                color: colors["admin_boundary"]!,
//                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 3)
//            )
//
//        case "road":
//            if classValue == "secondary" || classValue == "primary" || classValue == "highway" ||
//               classValue == "major_road" || classValue == "street" || classValue == "tertiary" {
//                let startZoom = 16
//                let tileZoom = tile.z
//                let difference = Double(tileZoom - startZoom)
//                let factor = pow(2.0, difference)
//                return FeatureStyle(
//                    key: 201,
//                    color: colors["road_major"]!,
//                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 40.0 * factor)
//                )
//            }
//            
//            if classValue == "service" {
//                let startZoom = 16
//                let tileZoom = tile.z
//                let difference = Double(tileZoom - startZoom)
//                let factor = pow(2.0, difference)
//                return FeatureStyle(
//                    key: 200,
//                    color: colors["road_major"]!,
//                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 25.0 * factor)
//                )
//            }
//            
//            return FeatureStyle(
//                key: fallbackKey, // Bottom-most
//                color: colors["fallback"]!,
//                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 1)
//            )
//
//        case "building":
//            return FeatureStyle(
//                key: 210, // Topmost layer
//                color: colors["building"]!,
//                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0) // Filled polygon
//            )
//        case "border":
//            return FeatureStyle(
//                key: 211,
//                color: colors["border"]!,
//                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
//            )

        default:
            return FeatureStyle(
                key: fallbackKey, // Bottom-most
                color: colors["fallback"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 1)
            )
        }
    }
}


