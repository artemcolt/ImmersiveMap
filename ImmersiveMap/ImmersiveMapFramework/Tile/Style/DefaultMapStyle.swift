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
            "border": SIMD4<Float>(1.0, 0.0, 0.0, 1.0),
            
            "building": SIMD4<Float>(0.8, 0.7, 0.6, 0.8),         // Warm beige
            "park": SIMD4<Float>(0.55, 0.75, 0.5, 0.7),            // Park green
            "residential": SIMD4<Float>(0.92, 0.9, 0.85, 0.6),     // Light beige
            "industrial": SIMD4<Float>(0.85, 0.82, 0.78, 0.7),     // Warm gray
            "farmland": SIMD4<Float>(0.86, 0.8, 0.6, 0.6),         // Tan
            "railway": SIMD4<Float>(0.5, 0.5, 0.5, 1.0),           // Mid gray
            "aeroway": SIMD4<Float>(0.88, 0.88, 0.9, 0.9)          // Pale concrete
        ]
        
        if data.layerName.hasSuffix("label") {
            return FeatureStyle(
                key: 2,
                color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0),
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )
        }
        
        switch data.layerName {
        case "background":
            return FeatureStyle(
                key: 1,
                color: colors["background"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )
        case "landcover":
            if tile.z > 13 {
                return FeatureStyle(
                    key: fallbackKey,
                    color: colors["fallback"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }
            if classValue == "forest" {
                if tile.z <= 11 {
                    return FeatureStyle(
                        key: fallbackKey,
                        color: colors["fallback"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                    )
                }
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
            
        case "waterway":
            if tile.z < 8 {
                return FeatureStyle(
                    key: fallbackKey,
                    color: colors["fallback"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }
            let lineWidth: Double
            if classValue == "river" || classValue == "canal" {
                lineWidth = 3
            } else {
                lineWidth = 2
            }
            return FeatureStyle(
                key: 22, // Above water polygons
                color: colors["river"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: lineWidth)
            )

        case "admin":
            if let adminLevel = properties["admin_level"]?.uintValue {
                if adminLevel == 1 {
                    return FeatureStyle(
                        key: 102, // Above water
                        color: colors["admin_level_1"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 4)
                    )
                } else if adminLevel == 2 {
                    return FeatureStyle(
                        key: 101,
                        color: colors["admin_boundary"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 4)
                    )
                }
            }
            return FeatureStyle(
                key: 100,
                color: colors["admin_boundary"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 5)
            )

        case "road":
            if classValue == "secondary" || classValue == "primary" || classValue == "highway" ||
               classValue == "major_road" || classValue == "street" || classValue == "tertiary" {
                let startZoom = 16
                let tileZoom = tile.z
                let difference = Double(tileZoom - startZoom)
                let factor = pow(2.0, difference)
                let roadColor: SIMD4<Float>
                if tileZoom <= 7 {
                    roadColor = SIMD4<Float>(0.75, 0.75, 0.75, 0.5)
                } else if tileZoom <= 9 {
                    roadColor = SIMD4<Float>(0.85, 0.85, 0.85, 0.8)
                } else {
                    roadColor = colors["road_major"]!
                }
                let minWidth: Double
                if tileZoom <= 10 {
                    minWidth = 6
                } else if tileZoom <= 12 {
                    minWidth = 4
                } else {
                    minWidth = 0
                }
                return FeatureStyle(
                    key: 201,
                    color: roadColor,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: max(40.0 * factor, minWidth))
                )
            }
            
            if classValue == "service" {
                let startZoom = 16
                let tileZoom = tile.z
                let difference = Double(tileZoom - startZoom)
                let factor = pow(2.0, difference)
                let roadColor: SIMD4<Float>
                if tileZoom <= 7 {
                    roadColor = SIMD4<Float>(0.7, 0.7, 0.7, 0.45)
                } else if tileZoom <= 9 {
                    roadColor = SIMD4<Float>(0.8, 0.8, 0.8, 0.75)
                } else {
                    roadColor = colors["road_major"]!
                }
                let minWidth: Double
                if tileZoom <= 10 {
                    minWidth = 4
                } else if tileZoom <= 12 {
                    minWidth = 3
                } else {
                    minWidth = 0
                }
                return FeatureStyle(
                    key: 200,
                    color: roadColor,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: max(25.0 * factor, minWidth))
                )
            }
            
            return FeatureStyle(
                key: fallbackKey, // Bottom-most
                color: colors["fallback"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 1)
            )

        case "building":
            return FeatureStyle(
                key: 210, // Topmost layer
                color: colors["building"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0) // Filled polygon
            )
            
        case "landuse", "landuse_overlay":
            if tile.z < 9 {
                return FeatureStyle(
                    key: fallbackKey,
                    color: colors["fallback"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }
            switch classValue {
            case "park", "cemetery", "pitch":
                if tile.z <= 13 {
                    return FeatureStyle(
                        key: fallbackKey,
                        color: colors["fallback"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                    )
                }
                return FeatureStyle(
                    key: 30,
                    color: colors["park"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "residential", "suburb", "neighbourhood":
                if tile.z <= 13 {
                    return FeatureStyle(
                        key: fallbackKey,
                        color: colors["fallback"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                    )
                }
                return FeatureStyle(
                    key: 31,
                    color: colors["residential"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "industrial", "commercial":
                if tile.z <= 13 {
                    return FeatureStyle(
                        key: fallbackKey,
                        color: colors["fallback"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                    )
                }
                return FeatureStyle(
                    key: 32,
                    color: colors["industrial"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "farmland", "farm", "orchard":
                if tile.z <= 13 {
                    return FeatureStyle(
                        key: fallbackKey,
                        color: colors["fallback"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                    )
                }
                return FeatureStyle(
                    key: 33,
                    color: colors["farmland"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "grass":
                if tile.z <= 13 {
                    return FeatureStyle(
                        key: fallbackKey,
                        color: colors["fallback"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                    )
                }
                return FeatureStyle(
                    key: 34,
                    color: colors["landcover_grass"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "wood", "scrub":
                return FeatureStyle(
                    key: 35,
                    color: colors["landcover_forest"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            default:
                if tile.z <= 13 {
                    return FeatureStyle(
                        key: fallbackKey,
                        color: colors["fallback"]!,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                    )
                }
                return FeatureStyle(
                    key: 30,
                    color: colors["landcover_grass"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }
            
        case "railway":
            if tile.z < 10 {
                return FeatureStyle(
                    key: fallbackKey,
                    color: colors["fallback"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }
            return FeatureStyle(
                key: 205, // Above roads
                color: colors["railway"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 8)
            )
            
        case "aeroway":
            if tile.z < 11 {
                return FeatureStyle(
                    key: fallbackKey,
                    color: colors["fallback"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }
            if classValue == "runway" || classValue == "taxiway" {
                return FeatureStyle(
                    key: 206,
                    color: colors["aeroway"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 12)
                )
            }
            return FeatureStyle(
                key: 206,
                color: colors["aeroway"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )
        case "border":
            return FeatureStyle(
                key: 211,
                color: colors["border"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )

        default:
            return FeatureStyle(
                key: fallbackKey, // Bottom-most
                color: colors["fallback"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 1)
            )
        }
    }
}
