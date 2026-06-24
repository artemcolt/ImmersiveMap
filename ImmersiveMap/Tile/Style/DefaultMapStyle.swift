// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import MetalKit


class DefaultMapStyle: ImmersiveMapStyle {
    static let preparedTileStyleRevisionValue: UInt32 = ImmersiveMapSettings.default.style.preparedTileStyleRevision

    private let buildingFillColor = SIMD4<Float>(0.94902, 0.92549, 0.890196, 1.0)
    private let roadLabelFillColor = SIMD3<Float>(0.54, 0.54, 0.52)
    private let roadLabelStrokeColor = SIMD3<Float>(1.0, 1.0, 1.0)
    private let placeLabelFillColor = SIMD3<Float>(0.38, 0.37, 0.35)
    private let emphasizedPlaceLabelFillColor = SIMD3<Float>(0.30, 0.29, 0.27)
    private let districtLabelFillColor = SIMD3<Float>(0.44, 0.43, 0.41)
    private let fallbackKey: UInt8 = 0
    private let labelKey: UInt8 = 2
    private let roadLowZoomFadeMask: Float = 2.0
    private let standardLabelStrokeWidthPx: Float = 5.4
    private let poiLabelStrokeWidthPx: Float = 7.2
    private let emphasizedLabelStrokeWidthPx: Float = 7.8
    private let roadLabelStrokeWidthPx: Float = 2.6
    private let zebraCrossingMinimumZoom: Int = 15
    private let onewayArrowKey: UInt8 = 209
    private let fallbackStyle: FeatureStyle
    private let mapBaseColors: ImmersiveMapBaseColors
    private let styleSettings: ImmersiveMapSettings.StyleSettings
    private let poiSpriteResolver = PoiSpriteResolver()

    init(settings: ImmersiveMapSettings.StyleSettings = ImmersiveMapSettings.default.style) {
        self.styleSettings = settings
        self.mapBaseColors = ImmersiveMapBaseColors(settings: settings.baseColors)
        fallbackStyle = FeatureStyle(
            key: fallbackKey,
            color: settings.fallbackFeatureColor,
            parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 100)
        )
    }
    
    func getMapBaseColors() -> ImmersiveMapBaseColors {
        return mapBaseColors
    }

    var preparedTileStyleRevision: UInt32 {
        styleSettings.preparedTileStyleRevision
    }

    private func makeLabelTextStyle(layerName: String,
                                    classValue: String?,
                                    tileZoom: Int,
                                    properties: [String: VectorTile_Tile.Value]) -> LabelTextStyle? {
        let normalizedLayerName = layerName.lowercased()
        let isPoiLabel = normalizedLayerName == "poi_label"
        let isHouseNumber = normalizedLayerName == "housenum_label"
        let normalizedClassValue = classValue?.lowercased()
        let normalizedTypeValue = properties["type"]?.stringValue.lowercased()
        let isAirport = normalizedLayerName == "airport_label"
        let isNaturalFeature = normalizedLayerName == "natural_label"
            && isNaturalLabelClass(normalizedClassValue)
        let isContinent = normalizedLayerName == "natural_label"
            && (normalizedClassValue == "continent" || normalizedTypeValue == "continent")
        let isOcean = normalizedLayerName == "natural_label"
            && isOceanLabelClass(normalizedClassValue)
        let isSea = normalizedLayerName == "natural_label"
            && isSeaLabelClass(normalizedClassValue)
        let capitalLevel = capitalLevel(properties)
        let isNationalCapital = capitalLevel == 2
        let isSmallCity = normalizedTypeValue == "town"
            || normalizedTypeValue == "village"
            || normalizedTypeValue == "hamlet"
            || normalizedTypeValue == "isolated_dwelling"
        let isCity = normalizedTypeValue == "city"
            || (normalizedTypeValue == nil && normalizedClassValue == "settlement")
        let isDistrict = normalizedClassValue == "settlement_subdivision"
            || normalizedTypeValue == "suburb"
            || normalizedTypeValue == "quarter"
            || normalizedTypeValue == "neighborhood"
            || normalizedTypeValue == "neighbourhood"
            || normalizedTypeValue == "locality"
            || normalizedTypeValue == "borough"
            || normalizedTypeValue == "district"
        let isLandmark = isAirport
            || isNaturalFeature
            || isLandmarkClass(normalizedTypeValue)
            || isLandmarkClass(normalizedClassValue)

        if isContinent {
            return LabelTextStyle(
                key: 1,
                fillColor: SIMD3<Float>(0.35, 0.35, 0.35),
                strokeColor: SIMD3<Float>(0.35, 0.35, 0.35),
                strokeWidthPx: 0.0,
                sizePx: continentLabelSize(for: tileZoom),
                weight: .bold
            )
        }

        if isOcean {
            let size = oceanLabelSize(for: tileZoom)
            return LabelTextStyle(
                key: 3,
                fillColor: SIMD3<Float>(0.10, 0.28, 0.72),
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: waterLabelStrokeWidth(for: size),
                sizePx: size,
                weight: .bold
            )
        }

        if isSea {
            let size = seaLabelSize(for: tileZoom)
            return LabelTextStyle(
                key: 4,
                fillColor: SIMD3<Float>(0.10, 0.28, 0.72),
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: waterLabelStrokeWidth(for: size),
                sizePx: size,
                weight: .bold
            )
        }

        if isNationalCapital {
            return LabelTextStyle(
                key: 2,
                fillColor: emphasizedPlaceLabelFillColor,
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: emphasizedLabelStrokeWidthPx,
                sizePx: capitalSize(level: capitalLevel, tileZoom: tileZoom),
                weight: .bold
            )
        }

        if capitalLevel > 0 {
            let size = capitalSize(level: capitalLevel, tileZoom: tileZoom)
            return LabelTextStyle(
                key: 20 + min(capitalLevel, 9),
                fillColor: emphasizedPlaceLabelFillColor,
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: standardLabelStrokeWidthPx,
                sizePx: size,
                weight: .thin
            )
        }

        if isCity {
            return LabelTextStyle(
                key: 30,
                fillColor: placeLabelFillColor,
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: standardLabelStrokeWidthPx,
                sizePx: cityLabelSize(for: tileZoom),
                weight: .thin
            )
        }

        if isSmallCity {
            return LabelTextStyle(
                key: 31,
                fillColor: placeLabelFillColor,
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: standardLabelStrokeWidthPx,
                sizePx: smallSettlementLabelSize(for: tileZoom),
                weight: .thin
            )
        }

        if isDistrict {
            return LabelTextStyle(
                key: 40,
                fillColor: districtLabelFillColor,
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: standardLabelStrokeWidthPx,
                sizePx: districtLabelSize(for: tileZoom),
                weight: .thin
            )
        }

        if isHouseNumber {
            return LabelTextStyle(
                key: 43,
                fillColor: houseNumberFillColor(),
                strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
                strokeWidthPx: 8.1,
                sizePx: houseNumberLabelSize(for: tileZoom),
                weight: .thin
            )
        }

        if isPoiLabel {
            if isLandmark,
               poiSpriteResolver.resolve(attributes: properties, layerName: normalizedLayerName) == nil {
                return makeLandmarkLabelTextStyle(tileZoom: tileZoom)
            }
            return makePoiLabelTextStyle(tileZoom: tileZoom, properties: properties)
        }

        if isLandmark {
            return makeLandmarkLabelTextStyle(tileZoom: tileZoom)
        }

        return nil
    }

    private func makeRoadLabelTextStyle() -> LabelTextStyle {
        return LabelTextStyle(
            key: 80,
            fillColor: roadLabelFillColor,
            strokeColor: roadLabelStrokeColor,
            strokeWidthPx: roadLabelStrokeWidthPx,
            sizePx: 36.0,
            weight: .thin
        )
    }

    private func makeLandmarkLabelTextStyle(tileZoom: Int) -> LabelTextStyle {
        LabelTextStyle(
            key: 41,
            fillColor: roadLabelFillColor,
            strokeColor: roadLabelStrokeColor,
            strokeWidthPx: emphasizedLabelStrokeWidthPx,
            sizePx: landmarkLabelSize(for: tileZoom),
            weight: .thin
        )
    }

    private func makePoiLabelTextStyle(tileZoom: Int,
                                       properties: [String: VectorTile_Tile.Value]) -> LabelTextStyle {
        let appearance = poiLabelAppearance(properties: properties)
        return LabelTextStyle(
            key: appearance.key,
            fillColor: appearance.fillColor,
            strokeColor: SIMD3<Float>(1.0, 1.0, 1.0),
            strokeWidthPx: poiLabelStrokeWidthPx,
            sizePx: poiLabelSize(for: tileZoom),
            weight: .thin
        )
    }

    private func poiLabelAppearance(properties: [String: VectorTile_Tile.Value]) -> (key: Int, fillColor: SIMD3<Float>) {
        switch poiSpriteResolver.resolve(attributes: properties, layerName: "poi_label") {
        case .restaurant?:
            return (420, SIMD3<Float>(0.84, 0.42, 0.24))
        case .cafe?:
            return (421, SIMD3<Float>(0.72, 0.50, 0.30))
        case .bar?:
            return (422, SIMD3<Float>(0.69, 0.34, 0.41))
        case .park?:
            return (423, SIMD3<Float>(0.22, 0.56, 0.30))
        case .museum?:
            return (424, SIMD3<Float>(0.37, 0.45, 0.78))
        case .hospital?:
            return (425, SIMD3<Float>(0.84, 0.28, 0.30))
        case .school?:
            return (426, SIMD3<Float>(0.30, 0.49, 0.78))
        case .airport?:
            return (427, SIMD3<Float>(0.24, 0.57, 0.77))
        case .stadium?:
            return (428, SIMD3<Float>(0.12, 0.57, 0.53))
        case .hotel?:
            return (429, SIMD3<Float>(0.55, 0.40, 0.74))
        case .shopping?:
            return (430, SIMD3<Float>(0.80, 0.34, 0.64))
        case .gasStation?:
            return (431, SIMD3<Float>(0.21, 0.61, 0.72))
        case .pharmacy?:
            return (432, SIMD3<Float>(0.16, 0.63, 0.47))
        case .viewpoint?:
            return (433, SIMD3<Float>(0.70, 0.53, 0.22))
        case nil:
            return (42, roadLabelFillColor)
        }
    }

    private func makeRoadGeometryStyle(lineWidth: Double) -> TileMvtParser.ParseGeometryStyleData {
        TileMvtParser.ParseGeometryStyleData(lineWidth: lineWidth,
                                             lineCapRound: true,
                                             lineJoinRound: true)
    }

    private func makeDashedRoadGeometryStyle(lineWidth: Double,
                                             dashLength: Double,
                                             dashGap: Double) -> TileMvtParser.ParseGeometryStyleData {
        TileMvtParser.ParseGeometryStyleData(lineWidth: lineWidth,
                                             lineCapRound: true,
                                             lineJoinRound: false,
                                             dashLength: dashLength,
                                             dashGap: dashGap)
    }

    private func makeSquareDashedRoadGeometryStyle(lineWidth: Double,
                                                   dashLength: Double,
                                                   dashGap: Double) -> TileMvtParser.ParseGeometryStyleData {
        TileMvtParser.ParseGeometryStyleData(lineWidth: lineWidth,
                                             lineCapRound: false,
                                             lineJoinRound: false,
                                             dashLength: dashLength,
                                             dashGap: dashGap,
                                             dashResetsPerSegment: true)
    }

    private func makeRoadCasingColor(from fillColor: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4<Float>(max(fillColor.x - 0.22, 0.0),
                     max(fillColor.y - 0.22, 0.0),
                     max(fillColor.z - 0.22, 0.0),
                     fillColor.w)
    }

    private func makeBridgeShadowColor(from fillColor: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4<Float>(max(fillColor.x - 0.12, 0.0),
                     max(fillColor.y - 0.12, 0.0),
                     max(fillColor.z - 0.12, 0.0),
                     min(max(fillColor.w, 0.82), 0.9))
    }

    private func makeRoadDetailColor(from fillColor: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4<Float>(max(fillColor.x - 0.40, 0.0),
                     max(fillColor.y - 0.40, 0.0),
                     max(fillColor.z - 0.40, 0.0),
                     min(fillColor.w, 0.30))
    }

    private func isBridgeRoad(properties: [String: VectorTile_Tile.Value]) -> Bool {
        let structureValue = properties["structure"]?.stringValue.lowercased() ?? ""
        let brunnelValue = properties["brunnel"]?.stringValue.lowercased() ?? ""
        let locationValue = properties["location"]?.stringValue.lowercased() ?? ""
        let layerValue = properties["layer"].flatMap(parseIntValue) ?? 0

        if isTruthy(properties["bridge"]) {
            return true
        }

        return structureValue == "bridge"
            || brunnelValue == "bridge"
            || locationValue.contains("bridge")
            || locationValue.contains("elevated")
            || layerValue > 0
    }

    private func bridgeOverlayBaseKey(for style: FeatureStyle) -> UInt8? {
        switch style.key {
        case 172:
            return 40
        case 175:
            return 50
        case 176:
            return 60
        case 177:
            return 70
        case 178:
            return 10
        case 179:
            return 20
        case 180:
            return 30
        case 181:
            return 80
        case 182:
            return 90
        case 190:
            return 100
        case 191:
            return 110
        case 192:
            return 120
        case 193:
            return 130
        case 194:
            return 140
        case 195:
            return 150
        case 196:
            return 160
        case 199:
            return 170
        case 200, 202:
            return 180
        case 201, 203:
            return 190
        case 205:
            return 200
        default:
            return nil
        }
    }

    private func makeBridgeStyle(baseStyle: FeatureStyle) -> FeatureStyle {
        guard let baseKey = bridgeOverlayBaseKey(for: baseStyle) else {
            return baseStyle
        }

        let basePasses = baseStyle.resolvedLineRenderPasses.filter { $0.parseGeometryStyleData.lineWidth > 0 }
        guard basePasses.isEmpty == false else {
            return baseStyle
        }

        let maxLineWidth = basePasses.reduce(baseStyle.parseGeometryStyleData.lineWidth) { partial, pass in
            max(partial, pass.parseGeometryStyleData.lineWidth)
        }

        var bridgePasses: [LineRenderPass] = []
        bridgePasses.reserveCapacity(basePasses.count + 2)
        bridgePasses.append(
            LineRenderPass(
                key: baseKey,
                color: makeBridgeShadowColor(from: baseStyle.color),
                lowZoomFadeMask: baseStyle.lowZoomFadeMask,
                parseGeometryStyleData: makeRoadGeometryStyle(
                    lineWidth: maxLineWidth + max(2.0, maxLineWidth * 0.18)
                ),
                includeRoadLabelPath: false,
                placement: .bridgeOverlay,
                roadPassRole: .shadow
            )
        )

        var nextKey = baseKey + 1
        if basePasses.count == 1, basePasses[0].parseGeometryStyleData.usesDashPattern == false {
            bridgePasses.append(
                LineRenderPass(
                    key: nextKey,
                    color: makeRoadCasingColor(from: basePasses[0].color),
                    lowZoomFadeMask: basePasses[0].lowZoomFadeMask,
                    parseGeometryStyleData: makeRoadGeometryStyle(
                        lineWidth: basePasses[0].parseGeometryStyleData.lineWidth
                            + max(1.0, basePasses[0].parseGeometryStyleData.lineWidth * 0.1)
                    ),
                    includeRoadLabelPath: false,
                    placement: .bridgeOverlay,
                    roadPassRole: .casing
                )
            )
            nextKey += 1
        }

        for basePass in basePasses {
            bridgePasses.append(
                LineRenderPass(
                    key: nextKey,
                    color: basePass.color,
                    lowZoomFadeMask: basePass.lowZoomFadeMask,
                    parseGeometryStyleData: basePass.parseGeometryStyleData,
                    includeRoadLabelPath: basePass.includeRoadLabelPath,
                    placement: .bridgeOverlay,
                    roadPassRole: basePass.roadPassRole
                )
            )
            nextKey += 1
        }

        let rootPass = bridgePasses.last(where: { $0.includeRoadLabelPath }) ?? bridgePasses.last!
        return FeatureStyle(
            key: rootPass.key,
            color: rootPass.color,
            lowZoomFadeMask: rootPass.lowZoomFadeMask,
            parseGeometryStyleData: rootPass.parseGeometryStyleData,
            includeRoadLabelPath: rootPass.includeRoadLabelPath,
            linePlacement: .bridgeOverlay,
            lineRenderPasses: bridgePasses,
            roadClassPriority: baseStyle.roadClassPriority,
            roadLabelTextStyle: baseStyle.roadLabelTextStyle,
            roadDecorationKind: baseStyle.roadDecorationKind
        )
    }

    private func bridgeifyRoadStyleIfNeeded(_ style: FeatureStyle,
                                            properties: [String: VectorTile_Tile.Value],
                                            tileZoom: Int) -> FeatureStyle {
        guard style.key != fallbackKey,
              tileZoom >= 12,
              isBridgeRoad(properties: properties) else {
            return style
        }
        return makeBridgeStyle(baseStyle: style)
    }

    private func makeDualPassRoadStyle(fillKey: UInt8,
                                       casingKey: UInt8,
                                       fillColor: SIMD4<Float>,
                                       fillWidth: Double,
                                       roadClassPriority: Int,
                                       includeRoadLabelPath: Bool = true,
                                       roadLabelTextStyle: LabelTextStyle? = nil) -> FeatureStyle {
        let fillGeometryStyle = makeRoadGeometryStyle(lineWidth: fillWidth)
        let casingGeometryStyle = makeRoadGeometryStyle(lineWidth: fillWidth * 1.35)
        let casingColor = makeRoadCasingColor(from: fillColor)

        return FeatureStyle(
            key: fillKey,
            color: fillColor,
            lowZoomFadeMask: roadLowZoomFadeMask,
            parseGeometryStyleData: fillGeometryStyle,
            includeRoadLabelPath: includeRoadLabelPath,
            lineRenderPasses: [
                LineRenderPass(key: casingKey,
                               color: casingColor,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: casingGeometryStyle,
                               includeRoadLabelPath: false,
                               roadPassRole: .casing),
                LineRenderPass(key: fillKey,
                               color: fillColor,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: fillGeometryStyle,
                               includeRoadLabelPath: includeRoadLabelPath,
                               roadPassRole: .fill)
            ],
            roadClassPriority: roadClassPriority,
            roadLabelTextStyle: roadLabelTextStyle
        )
    }

    private func makeSinglePassRoadStyle(key: UInt8,
                                         fillColor: SIMD4<Float>,
                                         fillWidth: Double,
                                         roadClassPriority: Int,
                                         includeRoadLabelPath: Bool = false,
                                         roadLabelTextStyle: LabelTextStyle? = nil) -> FeatureStyle {
        FeatureStyle(
            key: key,
            color: fillColor,
            lowZoomFadeMask: roadLowZoomFadeMask,
            parseGeometryStyleData: makeRoadGeometryStyle(lineWidth: fillWidth),
            includeRoadLabelPath: includeRoadLabelPath,
            roadClassPriority: roadClassPriority,
            roadLabelTextStyle: roadLabelTextStyle
        )
    }

    private func makeOnewayArrowPass(fillColor: SIMD4<Float>,
                                     lineWidth: Double,
                                     placement: LinePlacement,
                                     lowZoomFadeMask: Float) -> LineRenderPass {
        LineRenderPass(
            key: onewayArrowKey,
            color: makeRoadDetailColor(from: fillColor),
            lowZoomFadeMask: lowZoomFadeMask,
            parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: lineWidth),
            includeRoadLabelPath: false,
            placement: placement,
            roadPassRole: .detail
        )
    }

    private func shouldUseOnewayArrowDecoration(properties: [String: VectorTile_Tile.Value],
                                                normalizedRoadClass: String?,
                                                tileZoom: Int) -> Bool {
        guard tileZoom >= styleSettings.flatSeparateRoadRenderingMinimumZoom,
              isTruthy(properties["oneway"]),
              let normalizedRoadClass else {
            return false
        }

        switch normalizedRoadClass {
        case "motorway",
             "motorway_link",
             "trunk",
             "trunk_link",
             "primary",
             "primary_link",
             "secondary",
             "secondary_link",
             "tertiary",
             "tertiary_link",
             "major_road",
             "street",
             "highway",
             "minor",
             "service",
             "residential",
             "driveway",
             "parking_aisle",
             "alley",
             "living_street",
             "street_limited",
             "unclassified":
            return true
        default:
            return false
        }
    }

    private func decorateRoadStyleIfNeeded(_ style: FeatureStyle,
                                           properties: [String: VectorTile_Tile.Value],
                                           normalizedRoadClass: String?,
                                           tileZoom: Int) -> FeatureStyle {
        guard shouldUseOnewayArrowDecoration(properties: properties,
                                             normalizedRoadClass: normalizedRoadClass,
                                             tileZoom: tileZoom) else {
            return style
        }

        let basePasses = style.resolvedLineRenderPasses.filter { $0.parseGeometryStyleData.lineWidth > 0 }
        guard let fillPass = basePasses.last(where: { $0.roadPassRole == .fill }) ?? basePasses.last else {
            return style
        }

        var decoratedPasses = style.resolvedLineRenderPasses
        decoratedPasses.append(
            makeOnewayArrowPass(fillColor: fillPass.color,
                                lineWidth: fillPass.parseGeometryStyleData.lineWidth,
                                placement: style.linePlacement,
                                lowZoomFadeMask: style.lowZoomFadeMask)
        )

        return FeatureStyle(
            key: style.key,
            color: style.color,
            lowZoomFadeMask: style.lowZoomFadeMask,
            parseGeometryStyleData: style.parseGeometryStyleData,
            includeRoadLabelPath: style.includeRoadLabelPath,
            linePlacement: style.linePlacement,
            lineRenderPasses: decoratedPasses,
            roadClassPriority: style.roadClassPriority,
            usesExtrusion: style.usesExtrusion,
            extrusionHeightScale: style.extrusionHeightScale,
            extrusionAnchorZoom: style.extrusionAnchorZoom,
            extrusionFallbackHeight: style.extrusionFallbackHeight,
            labelTextStyle: style.labelTextStyle,
            roadLabelTextStyle: style.roadLabelTextStyle,
            roadDecorationKind: .onewayArrow
        )
    }

    private func makeRoadFillWidth(tileZoom: Int,
                                   baseWidth: Double,
                                   minWidthAt10: Double,
                                   minWidthAt12: Double,
                                   startZoom: Int = 16) -> Double {
        let factor = pow(2.0, Double(tileZoom - startZoom))
        let minWidth: Double
        if tileZoom <= 10 {
            minWidth = minWidthAt10
        } else if tileZoom <= 12 {
            minWidth = minWidthAt12
        } else {
            minWidth = 0
        }
        return max(baseWidth * factor, minWidth)
    }

    private func makeZebraCrossingStyle(tileZoom: Int) -> FeatureStyle {
        let crossingWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 44.0,
                                              minWidthAt10: 6.0,
                                              minWidthAt12: 6.0)
        let geometryStyle = makeRoadGeometryStyle(lineWidth: crossingWidth)
        let zebraColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)

        return FeatureStyle(
            key: 208,
            color: zebraColor,
            lowZoomFadeMask: roadLowZoomFadeMask,
            parseGeometryStyleData: geometryStyle,
            lineRenderPasses: [
                LineRenderPass(key: 208,
                               color: zebraColor,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: geometryStyle,
                               includeRoadLabelPath: false,
                               roadPassRole: .overlay)
            ],
            roadClassPriority: 110,
            roadDecorationKind: .zebraCrossing
        )
    }

    private func makeStepsRoadStyle(tileZoom: Int,
                                    colors: [String: SIMD4<Float>]) -> FeatureStyle {
        let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                          baseWidth: 12.0,
                                          minWidthAt10: 2.0,
                                          minWidthAt12: 2.0)
        let stripeLength = max(2.0, fillWidth * 0.45)
        let stripeGap = max(2.0, fillWidth * 0.55)
        let baseColor = colors["road_steps_base"]!
        let stripeColor = colors["road_steps"]!
        let baseGeometryStyle = makeRoadGeometryStyle(lineWidth: fillWidth)
        let stripeGeometryStyle = makeSquareDashedRoadGeometryStyle(lineWidth: fillWidth,
                                                                    dashLength: stripeLength,
                                                                    dashGap: stripeGap)

        return FeatureStyle(
            key: 177,
            color: baseColor,
            lowZoomFadeMask: roadLowZoomFadeMask,
            parseGeometryStyleData: baseGeometryStyle,
            lineRenderPasses: [
                LineRenderPass(key: 177,
                               color: baseColor,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: baseGeometryStyle,
                               includeRoadLabelPath: false,
                               roadPassRole: .fill),
                LineRenderPass(key: 183,
                               color: stripeColor,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: stripeGeometryStyle,
                               includeRoadLabelPath: false,
                               roadPassRole: .detail)
            ],
            roadClassPriority: 15
        )
    }

    private func makeRailwayStyle(colors: [String: SIMD4<Float>]) -> FeatureStyle {
        let borderWidth: Double = 10.0
        let fillWidth: Double = 8.0
        let sleeperWidth: Double = 6.0
        let sleeperLength: Double = 20.0
        let sleeperGap: Double = 14.0
        let borderGeometryStyle = makeRoadGeometryStyle(lineWidth: borderWidth)
        let fillGeometryStyle = makeRoadGeometryStyle(lineWidth: fillWidth)
        let sleeperGeometryStyle = makeSquareDashedRoadGeometryStyle(lineWidth: sleeperWidth,
                                                                     dashLength: sleeperLength,
                                                                     dashGap: sleeperGap)

        return FeatureStyle(
            key: 205,
            color: colors["railway_border"]!,
            lowZoomFadeMask: roadLowZoomFadeMask,
            parseGeometryStyleData: borderGeometryStyle,
            lineRenderPasses: [
                LineRenderPass(key: 205,
                               color: colors["railway_border"]!,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: borderGeometryStyle,
                               includeRoadLabelPath: false,
                               roadPassRole: .casing),
                LineRenderPass(key: 206,
                               color: colors["railway_fill"]!,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: fillGeometryStyle,
                               includeRoadLabelPath: false,
                               roadPassRole: .fill),
                LineRenderPass(key: 207,
                               color: colors["railway_sleepers"]!,
                               lowZoomFadeMask: roadLowZoomFadeMask,
                               parseGeometryStyleData: sleeperGeometryStyle,
                               includeRoadLabelPath: false,
                               roadPassRole: .detail)
            ],
            roadClassPriority: 75
        )
    }

    private func makeSupplementalRoadStyle(roadClass: String,
                                           tileZoom: Int,
                                           colors: [String: SIMD4<Float>]) -> FeatureStyle? {
        if roadClass == "steps" {
            return makeStepsRoadStyle(tileZoom: tileZoom, colors: colors)
        }

        switch roadClass {
        case "minor":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 40.0,
                                              minWidthAt10: 5.0,
                                              minWidthAt12: 4.0)
            let fillColor = colors["road_major"]!
            if tileZoom > 13 {
                return makeDualPassRoadStyle(fillKey: 182,
                                             casingKey: 184,
                                             fillColor: fillColor,
                                             fillWidth: fillWidth,
                                             roadClassPriority: 60,
                                             includeRoadLabelPath: false)
            }
            return makeSinglePassRoadStyle(key: 182,
                                           fillColor: fillColor,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 60)
        case "motorway":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 60.0,
                                              minWidthAt10: 10.0,
                                              minWidthAt12: 7.0)
            return makeSinglePassRoadStyle(key: 190,
                                           fillColor: colors["road_motorway"]!,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 95)
        case "motorway_link":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 30.0,
                                              minWidthAt10: 6.0,
                                              minWidthAt12: 4.0)
            return makeSinglePassRoadStyle(key: 191,
                                           fillColor: colors["road_motorway_link"]!,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 90)
        case "trunk":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 54.0,
                                              minWidthAt10: 9.0,
                                              minWidthAt12: 6.0)
            return makeSinglePassRoadStyle(key: 192,
                                           fillColor: colors["road_trunk"]!,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 90)
        case "trunk_link":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 28.0,
                                              minWidthAt10: 5.0,
                                              minWidthAt12: 4.0)
            return makeSinglePassRoadStyle(key: 193,
                                           fillColor: colors["road_trunk_link"]!,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 85)
        case "primary_link":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 26.0,
                                              minWidthAt10: 5.0,
                                              minWidthAt12: 4.0)
            return makeSinglePassRoadStyle(key: 194,
                                           fillColor: colors["road_primary_link"]!,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 82)
        case "secondary_link":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 24.0,
                                              minWidthAt10: 4.0,
                                              minWidthAt12: 3.0)
            return makeSinglePassRoadStyle(key: 195,
                                           fillColor: colors["road_secondary_link"]!,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 78)
        case "tertiary_link":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 22.0,
                                              minWidthAt10: 4.0,
                                              minWidthAt12: 3.0)
            return makeSinglePassRoadStyle(key: 196,
                                           fillColor: colors["road_tertiary_link"]!,
                                           fillWidth: fillWidth,
                                           roadClassPriority: 74)
        case "track":
            let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                              baseWidth: 14.0,
                                              minWidthAt10: 2.0,
                                              minWidthAt12: 2.0)
            return FeatureStyle(
                key: 176,
                color: colors["road_track"]!,
                lowZoomFadeMask: roadLowZoomFadeMask,
                parseGeometryStyleData: makeDashedRoadGeometryStyle(lineWidth: fillWidth,
                                                                    dashLength: max(2.0, fillWidth * 1.35),
                                                                    dashGap: max(2.0, fillWidth * 0.95)),
                roadClassPriority: 25
            )
        default:
            break
        }

        let descriptor: (key: UInt8, casingKey: UInt8?, colorName: String, baseWidth: Double, minWidthAt10: Double, minWidthAt12: Double)?
        switch roadClass {
        case "residential":
            descriptor = (170, nil, "road_residential", 24.0, 4.0, 3.0)
        case "unclassified":
            descriptor = (172, nil, "road_unclassified", 20.0, 4.0, 3.0)
        case "path":
            descriptor = nil
        case "cycleway":
            descriptor = (175, nil, "road_cycleway", 14.0, 3.0, 2.0)
        case "track":
            descriptor = nil
        case "footway":
            descriptor = (199, 198, "road_footway", 28.0, 4.0, 3.0)
        case "sidewalk":
            descriptor = (179, nil, "road_sidewalk", 10.0, 2.0, 2.0)
        case "trail":
            descriptor = (180, nil, "road_trail", 12.0, 2.0, 2.0)
        case "crossing":
            descriptor = (181, nil, "road_crossing", 10.0, 2.0, 2.0)
        case "minor":
            descriptor = nil
        default:
            descriptor = nil
        }

        guard let descriptor,
              let color = colors[descriptor.colorName] else {
            return nil
        }

        let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                          baseWidth: descriptor.baseWidth,
                                          minWidthAt10: descriptor.minWidthAt10,
                                          minWidthAt12: descriptor.minWidthAt12)
        if roadClass == "trail" {
            return FeatureStyle(
                key: descriptor.key,
                color: color,
                lowZoomFadeMask: roadLowZoomFadeMask,
                parseGeometryStyleData: makeDashedRoadGeometryStyle(lineWidth: fillWidth,
                                                                    dashLength: fillWidth * 1.6,
                                                                    dashGap: fillWidth * 1.1),
                roadClassPriority: 22
            )
        }
        if tileZoom > 13,
           let casingKey = descriptor.casingKey {
            return makeDualPassRoadStyle(fillKey: descriptor.key,
                                         casingKey: casingKey,
                                         fillColor: color,
                                         fillWidth: fillWidth,
                                         roadClassPriority: roadClassPriority(for: roadClass),
                                         includeRoadLabelPath: false)
        }
        return makeSinglePassRoadStyle(key: descriptor.key,
                                       fillColor: color,
                                       fillWidth: fillWidth,
                                       roadClassPriority: roadClassPriority(for: roadClass))
    }

    private func roadClassPriority(for roadClass: String) -> Int {
        switch roadClass {
        case "motorway":
            return 95
        case "motorway_link", "trunk":
            return 90
        case "trunk_link":
            return 85
        case "primary_link":
            return 82
        case "secondary", "primary", "highway", "major_road", "street", "tertiary":
            return 80
        case "secondary_link":
            return 78
        case "major_rail", "minor_rail", "service_rail":
            return 75
        case "tertiary_link":
            return 74
        case "minor":
            return 60
        case "service", "residential", "driveway", "parking_aisle", "alley", "living_street", "street_limited", "unclassified":
            return 50
        case "pedestrian":
            return 35
        case "track":
            return 25
        case "trail":
            return 22
        case "footway", "sidewalk", "path", "cycleway", "crossing":
            return 20
        case "steps":
            return 15
        default:
            return 10
        }
    }

    private func isLandmarkClass(_ classValue: String?) -> Bool {
        guard let value = normalizedLandmarkClassValue(classValue) else {
            return false
        }
        switch value {
        case "attraction",
             "airport",
             "airfield",
             "heliport",
             "tower",
             "watchtower",
             "bell_tower",
             "church",
             "cathedral",
             "chapel",
             "monastery",
             "abbey",
             "basilica",
             "temple",
             "mosque",
             "synagogue",
             "shrine",
             "square",
             "plaza",
             "piazza",
             "park",
             "national_park",
             "garden",
             "cemetery",
             "landmark",
             "museum",
             "monument",
             "memorial",
             "station",
             "railway_station",
             "university",
             "college",
             "hospital",
             "viewpoint",
             "tourism",
             "zoo",
             "stadium",
             "castle",
             "place_of_worship":
            return true
        default:
            return false
        }
    }

    private func normalizedLandmarkClassValue(_ value: String?) -> String? {
        value?
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func isNaturalLabelClass(_ classValue: String?) -> Bool {
        guard let value = classValue?.lowercased() else {
            return false
        }
        switch value {
        case "river",
             "stream",
             "canal",
             "bay",
             "reservoir",
             "water_feature",
             "landform":
            return true
        default:
            return false
        }
    }

    private func isOceanLabelClass(_ classValue: String?) -> Bool {
        guard let value = classValue?.lowercased() else {
            return false
        }
        switch value {
        case "ocean":
            return true
        default:
            return false
        }
    }

    private func isSeaLabelClass(_ classValue: String?) -> Bool {
        guard let value = classValue?.lowercased() else {
            return false
        }
        switch value {
        case "sea":
            return true
        default:
            return false
        }
    }

    private func capitalLevel(_ properties: [String: VectorTile_Tile.Value]) -> Int {
        let keyCandidates = ["capital", "captial"]
        for key in keyCandidates {
            if let value = properties[key],
               let parsed = parseIntValue(value) {
                return parsed
            }
        }
        return 0
    }

    private func parseIntValue(_ value: VectorTile_Tile.Value) -> Int? {
        if value.hasIntValue {
            return Int(value.intValue)
        }
        if value.hasSintValue {
            return Int(value.sintValue)
        }
        if value.hasUintValue {
            guard value.uintValue <= UInt64(Int.max) else { return nil }
            return Int(value.uintValue)
        }
        if value.hasFloatValue {
            return Int(value.floatValue)
        }
        if value.hasDoubleValue {
            return Int(value.doubleValue)
        }
        if value.hasBoolValue {
            return value.boolValue ? 1 : 0
        }
        if value.hasStringValue {
            let trimmed = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        }
        return nil
    }

    private func parseBoolValue(_ value: VectorTile_Tile.Value) -> Bool? {
        if value.hasBoolValue {
            return value.boolValue
        }
        if let intValue = parseIntValue(value) {
            return intValue != 0
        }
        if value.hasStringValue {
            let lowercased = value.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            switch lowercased {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                break
            }
        }
        return nil
    }

    private func isTruthy(_ value: VectorTile_Tile.Value?) -> Bool {
        guard let value else {
            return false
        }
        return parseBoolValue(value) ?? false
    }

    private func isUndergroundRailway(properties: [String: VectorTile_Tile.Value]) -> Bool {
        let locationValue = properties["location"]?.stringValue.lowercased() ?? ""
        let structureValue = properties["structure"]?.stringValue.lowercased() ?? ""
        let brunnelValue = properties["brunnel"]?.stringValue.lowercased() ?? ""
        let layerValue = properties["layer"].flatMap(parseIntValue) ?? 0

        return isTruthy(properties["underground"])
            || isTruthy(properties["tunnel"])
            || locationValue.contains("underground")
            || locationValue.contains("subterranean")
            || locationValue.contains("tunnel")
            || structureValue == "tunnel"
            || brunnelValue == "tunnel"
            || layerValue < 0
    }

    private func continentLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...9:
            return 52.0
        case 10:
            return 56.0
        default:
            return 60.0
        }
    }

    private func oceanLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...1:
            return 27.0
        case 2:
            return 24.0
        default:
            return 18.0
        }
    }

    private func seaLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...1:
            return 40.0
        case 2:
            return 34.0
        default:
            return 26.0
        }
    }

    private func waterLabelStrokeWidth(for sizePx: Float) -> Float {
        min(standardLabelStrokeWidthPx, sizePx * 0.14)
    }

    private func capitalSize(level: Int, tileZoom: Int) -> Float {
        let normalized = max(1, level)
        let baseSize: Float
        let minimumSize: Float
        switch tileZoom {
        case ...9:
            baseSize = 52.0
            minimumSize = 40.0
        case 10:
            baseSize = 56.0
            minimumSize = 42.0
        case 11:
            baseSize = 52.0
            minimumSize = 40.0
        case 12:
            baseSize = 48.0
            minimumSize = 38.0
        case 13:
            baseSize = 44.0
            minimumSize = 36.0
        default:
            baseSize = 42.0
            minimumSize = 34.0
        }
        if normalized <= 2 {
            return baseSize
        }
        return max(minimumSize, baseSize - Float(normalized - 2) * 4.0)
    }

    private func cityLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...9:
            return 30.0
        case 10:
            return 34.0
        case 11:
            return 38.0
        case 12:
            return 38.0
        case 13:
            return 36.0
        default:
            return 34.0
        }
    }

    private func smallSettlementLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...9:
            return 22.0
        case 10:
            return 26.0
        case 11:
            return 30.0
        case 12:
            return 34.0
        default:
            return 38.0
        }
    }

    private func districtLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...9:
            return 18.0
        case 10:
            return 22.0
        case 11:
            return 24.0
        case 12:
            return 26.0
        case 13:
            return 28.0
        default:
            return 30.0
        }
    }

    private func landmarkLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...9:
            return 18.0
        case 10:
            return 22.0
        case 11...12:
            return 26.0
        case 13:
            return 28.0
        default:
            return 30.0
        }
    }

    private func poiLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...12:
            return 20.0
        case 13:
            return 24.0
        case 14:
            return 26.0
        default:
            return 28.0
        }
    }

    private func houseNumberFillColor() -> SIMD3<Float> {
        SIMD3<Float>(buildingFillColor.x, buildingFillColor.y, buildingFillColor.z) * 0.5
    }

    private func houseNumberLabelSize(for tileZoom: Int) -> Float {
        switch tileZoom {
        case ...16:
            return 36.0
        case 17:
            return 39.0
        default:
            return 42.0
        }
    }
    
    func makeStyle(data: DetFeatureStyleData) -> FeatureStyle {
        let tile = data.tile
        let properties = data.properties
        let classValue = properties["class"]?.stringValue ?? properties["type"]?.stringValue
        let typeValue = properties["type"]?.stringValue
        let labelClassValue = properties["class"]?.stringValue

        // Color palette (RGBA, normalized to 0.0-1.0)
        let colors = [
            "admin_boundary": SIMD4<Float>(0.65, 0.65, 0.75, 1.0), // Soft purple-gray
            "admin_level_1": SIMD4<Float>(0.45, 0.55, 0.85, 1.0), // Deeper blue
            "water": mapBaseColors.getWaterColor(),
            "river": SIMD4<Float>(0.2, 0.5, 0.8, 1.0),           // Slightly darker blue
            "landcover_forest": SIMD4<Float>(0.2, 0.6, 0.4, 0.7), // Forest green
            "landcover_scrub": SIMD4<Float>(0.42, 0.68, 0.40, 0.64),
            "landcover_grass": mapBaseColors.getLandCoverColor(),
            "landcover_crop": SIMD4<Float>(0.62, 0.74, 0.42, 0.58),
            "landcover_snow": SIMD4<Float>(0.96, 0.97, 0.98, 0.86),
            "hillshade_shadow": SIMD4<Float>(0.30, 0.36, 0.40, 0.18),
            "hillshade_highlight": SIMD4<Float>(1.0, 1.0, 1.0, 0.16),
            "contour": SIMD4<Float>(0.58, 0.60, 0.52, 0.34),
            "road_major": SIMD4<Float>(0.9, 0.9, 0.9, 1.0),       // Near-white
            "road_minor": SIMD4<Float>(0.7, 0.7, 0.7, 1.0),       // Light gray
            "road_pedestrian": SIMD4<Float>(0.965, 0.965, 0.955, 1.0), // Near-background warm off-white
            "road_motorway": SIMD4<Float>(0.93, 0.54, 0.33, 1.0),
            "road_motorway_link": SIMD4<Float>(0.95, 0.66, 0.39, 1.0),
            "road_trunk": SIMD4<Float>(0.95, 0.68, 0.28, 1.0),
            "road_trunk_link": SIMD4<Float>(0.96, 0.76, 0.40, 1.0),
            "road_primary_link": SIMD4<Float>(0.90, 0.895, 0.88, 1.0),
            "road_secondary_link": SIMD4<Float>(0.885, 0.88, 0.865, 1.0),
            "road_tertiary_link": SIMD4<Float>(0.87, 0.865, 0.85, 1.0),
            "road_residential": SIMD4<Float>(0.82, 0.63, 0.63, 1.0),
            "road_living_street": SIMD4<Float>(0.73, 0.63, 0.83, 1.0),
            "road_unclassified": SIMD4<Float>(0.60, 0.67, 0.79, 1.0),
            "road_street_limited": SIMD4<Float>(0.47, 0.74, 0.82, 1.0),
            "road_path": SIMD4<Float>(0.33, 0.74, 0.56, 1.0),
            "road_cycleway": SIMD4<Float>(0.16, 0.71, 0.74, 1.0),
            "road_track": SIMD4<Float>(0.40, 0.39, 0.31, 1.0),
            "road_steps_base": SIMD4<Float>(0.94, 0.94, 0.925, 1.0),
            "road_steps": SIMD4<Float>(0.58, 0.56, 0.52, 1.0),
            "road_footway": SIMD4<Float>(0.948, 0.948, 0.936, 1.0),
            "road_sidewalk": SIMD4<Float>(0.985, 0.98, 0.965, 1.0),
            "road_trail": SIMD4<Float>(0.84, 0.85, 0.78, 1.0),
            "road_crossing": SIMD4<Float>(0.94, 0.94, 0.94, 1.0),
            "road_minor_local": SIMD4<Float>(0.54, 0.72, 0.65, 1.0),
            "road_misc": SIMD4<Float>(0.64, 0.64, 0.64, 1.0),
            "fallback": SIMD4<Float>(0.5, 0.5, 0.5, 0.5),          // Neutral gray
            "background": mapBaseColors.getTileBgColor(),
            "border": SIMD4<Float>(1.0, 0.0, 0.0, 1.0),
            
            "building": buildingFillColor,                             // Yandex-like light beige gray
            "park": SIMD4<Float>(0.55, 0.75, 0.5, 0.7),            // Park green
            "residential": SIMD4<Float>(0.92, 0.9, 0.85, 0.6),     // Light beige
            "industrial": SIMD4<Float>(0.85, 0.82, 0.78, 0.7),     // Warm gray
            "farmland": SIMD4<Float>(0.86, 0.8, 0.6, 0.6),         // Tan
            "railway_border": SIMD4<Float>(0.73, 0.81, 0.82, 1.0),
            "railway_fill": SIMD4<Float>(0.99, 0.99, 0.99, 1.0),
            "railway_sleepers": SIMD4<Float>(0.65, 0.74, 0.75, 1.0),
            "aeroway": SIMD4<Float>(0.88, 0.88, 0.9, 0.9)          // Pale concrete
        ]
        
        let name_en = properties["name_en"]?.stringValue
        if data.layerName.hasSuffix("label") || name_en == "Moscow" {
            if let labelTextStyle = makeLabelTextStyle(layerName: data.layerName,
                                                       classValue: labelClassValue,
                                                       tileZoom: tile.z,
                                                       properties: properties) {
                return FeatureStyle(
                    key: labelKey,
                    color: colors["fallback"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0),
                    labelTextStyle: labelTextStyle
                )
            }
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
            switch classValue?.lowercased() {
            case "forest", "wood":
                if tile.z <= 5 {
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
            case "scrub":
                return FeatureStyle(
                    key: 12,
                    color: colors["landcover_scrub"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "grass":
                return FeatureStyle(
                    key: 12, // Above forest
                    color: colors["landcover_grass"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "crop", "farmland":
                return FeatureStyle(
                    key: 12,
                    color: colors["landcover_crop"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            case "snow", "ice":
                return FeatureStyle(
                    key: 13,
                    color: colors["landcover_snow"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            default:
                return FeatureStyle(
                    key: 10,
                    color: colors["landcover_grass"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
                )
            }

        case "hillshade":
            if tile.z < 5 || tile.z > 13 {
                return fallbackStyle
            }
            let hillshadeClass = classValue?.lowercased()
            return FeatureStyle(
                key: 14,
                color: hillshadeClass == "highlight" ? colors["hillshade_highlight"]! : colors["hillshade_shadow"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )

        case "contour":
            if tile.z < 10 || tile.z > 15 {
                return fallbackStyle
            }
            return FeatureStyle(
                key: 15,
                color: colors["contour"]!,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: tile.z >= 13 ? 1.0 : 0.55)
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
                        lowZoomFadeMask: 1.0,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 6)
                    )
                } else if adminLevel == 2 {
                    return FeatureStyle(
                        key: 101,
                        color: colors["admin_boundary"]!,
                        lowZoomFadeMask: 1.0,
                        parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 6)
                    )
                }
            }
            return FeatureStyle(
                key: 100,
                color: colors["admin_boundary"]!,
                lowZoomFadeMask: 1.0,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 7.5)
            )

        case "road":
            let roadClassProperty = properties["class"]?.stringValue.lowercased()
            let roadTypeValue = properties["type"]?.stringValue.lowercased()
            if roadClassProperty == "path", roadTypeValue == "path" {
                return fallbackStyle
            }
            let normalizedRoadClass = roadClassProperty == "path"
                ? (roadTypeValue ?? roadClassProperty)
                : classValue?.lowercased()

            if normalizedRoadClass == "major_rail" ||
               normalizedRoadClass == "minor_rail" ||
               normalizedRoadClass == "service_rail" {
                guard tile.z >= 13 else {
                    return fallbackStyle
                }
                guard isUndergroundRailway(properties: properties) == false else {
                    return fallbackStyle
                }
                return bridgeifyRoadStyleIfNeeded(makeRailwayStyle(colors: colors),
                                                  properties: properties,
                                                  tileZoom: tile.z)
            }

            if normalizedRoadClass == "footway" {
                let tileZoom = tile.z
                let footwayColor = colors["road_footway"]!
                let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                                  baseWidth: 10.0,
                                                  minWidthAt10: 2.0,
                                                  minWidthAt12: 2.0)
                return bridgeifyRoadStyleIfNeeded(
                    decorateRoadStyleIfNeeded(
                        makeSinglePassRoadStyle(key: 178,
                                                fillColor: footwayColor,
                                                fillWidth: fillWidth,
                                                roadClassPriority: 20),
                        properties: properties,
                        normalizedRoadClass: normalizedRoadClass,
                        tileZoom: tile.z
                    ),
                    properties: properties,
                    tileZoom: tile.z
                )
            }

            if normalizedRoadClass == "crossing" {
                guard tile.z >= zebraCrossingMinimumZoom else {
                    return fallbackStyle
                }
                return makeZebraCrossingStyle(tileZoom: tile.z)
            }

            if normalizedRoadClass == "pedestrian" {
                let tileZoom = tile.z
                let roadColor = colors["road_pedestrian"]!
                let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                                  baseWidth: 28.0,
                                                  minWidthAt10: 4.0,
                                                  minWidthAt12: 3.0)
                let style: FeatureStyle
                if tileZoom > 13 {
                    style = makeDualPassRoadStyle(fillKey: 199,
                                                  casingKey: 198,
                                                  fillColor: roadColor,
                                                  fillWidth: fillWidth,
                                                  roadClassPriority: 35,
                                                  includeRoadLabelPath: false)
                } else {
                    style = FeatureStyle(
                        key: 199,
                        color: roadColor,
                        lowZoomFadeMask: roadLowZoomFadeMask,
                        parseGeometryStyleData: makeRoadGeometryStyle(lineWidth: fillWidth),
                        roadClassPriority: 35
                    )
                }
                return bridgeifyRoadStyleIfNeeded(style,
                                                  properties: properties,
                                                  tileZoom: tile.z)
            }

            if normalizedRoadClass == "sidewalk" || normalizedRoadClass == "path" {
                let tileZoom = tile.z
                let sidewalkColor = colors["road_sidewalk"]!
                let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                                  baseWidth: 8.0,
                                                  minWidthAt10: 2.0,
                                                  minWidthAt12: 2.0)
                return bridgeifyRoadStyleIfNeeded(
                    decorateRoadStyleIfNeeded(
                        makeSinglePassRoadStyle(key: 179,
                                                fillColor: sidewalkColor,
                                                fillWidth: fillWidth,
                                                roadClassPriority: 20),
                        properties: properties,
                        normalizedRoadClass: normalizedRoadClass,
                        tileZoom: tile.z
                    ),
                    properties: properties,
                    tileZoom: tile.z
                )
            }

            if normalizedRoadClass == "secondary" || normalizedRoadClass == "primary" || normalizedRoadClass == "highway" ||
               normalizedRoadClass == "major_road" || normalizedRoadClass == "street" || normalizedRoadClass == "tertiary" {
                let tileZoom = tile.z
                let roadColor: SIMD4<Float>
                if tileZoom <= 7 {
                    roadColor = SIMD4<Float>(0.75, 0.75, 0.75, 0.5)
                } else if tileZoom <= 9 {
                    roadColor = SIMD4<Float>(0.85, 0.85, 0.85, 0.8)
                } else {
                    roadColor = colors["road_major"]!
                }
                let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                                  baseWidth: 80.0,
                                                  minWidthAt10: 12.0,
                                                  minWidthAt12: 8.0)
                let roadLabelTextStyle = makeRoadLabelTextStyle()
                let style: FeatureStyle
                if tileZoom > 13 {
                    style = makeDualPassRoadStyle(fillKey: 203,
                                                  casingKey: 201,
                                                  fillColor: roadColor,
                                                  fillWidth: fillWidth,
                                                  roadClassPriority: 80,
                                                  roadLabelTextStyle: roadLabelTextStyle)
                } else {
                    style = FeatureStyle(
                        key: 201,
                        color: roadColor,
                        lowZoomFadeMask: roadLowZoomFadeMask,
                        parseGeometryStyleData: makeRoadGeometryStyle(lineWidth: fillWidth),
                        includeRoadLabelPath: true,
                        roadClassPriority: 80,
                        roadLabelTextStyle: roadLabelTextStyle
                    )
                }
                return bridgeifyRoadStyleIfNeeded(
                    decorateRoadStyleIfNeeded(style,
                                              properties: properties,
                                              normalizedRoadClass: normalizedRoadClass,
                                              tileZoom: tile.z),
                    properties: properties,
                    tileZoom: tile.z
                )
            }
            
            if normalizedRoadClass == "service" || normalizedRoadClass == "residential" ||
               normalizedRoadClass == "driveway" ||
               normalizedRoadClass == "parking_aisle" || normalizedRoadClass == "alley" ||
               normalizedRoadClass == "living_street" || normalizedRoadClass == "street_limited" {
                let tileZoom = tile.z
                let roadColor: SIMD4<Float>
                if tileZoom <= 7 {
                    roadColor = SIMD4<Float>(0.7, 0.7, 0.7, 0.45)
                } else if tileZoom <= 9 {
                    roadColor = SIMD4<Float>(0.8, 0.8, 0.8, 0.75)
                } else {
                    roadColor = colors["road_major"]!
                }
                let fillWidth = makeRoadFillWidth(tileZoom: tileZoom,
                                                  baseWidth: 50.0,
                                                  minWidthAt10: 8.0,
                                                  minWidthAt12: 6.0)
                let roadLabelTextStyle = makeRoadLabelTextStyle()
                let style: FeatureStyle
                if tileZoom > 13 {
                    style = makeDualPassRoadStyle(fillKey: 202,
                                                  casingKey: 200,
                                                  fillColor: roadColor,
                                                  fillWidth: fillWidth,
                                                  roadClassPriority: 50,
                                                  roadLabelTextStyle: roadLabelTextStyle)
                } else {
                    style = FeatureStyle(
                        key: 200,
                        color: roadColor,
                        lowZoomFadeMask: roadLowZoomFadeMask,
                        parseGeometryStyleData: makeRoadGeometryStyle(lineWidth: fillWidth),
                        includeRoadLabelPath: true,
                        roadClassPriority: 50,
                        roadLabelTextStyle: roadLabelTextStyle
                    )
                }
                return bridgeifyRoadStyleIfNeeded(
                    decorateRoadStyleIfNeeded(style,
                                              properties: properties,
                                              normalizedRoadClass: normalizedRoadClass,
                                              tileZoom: tile.z),
                    properties: properties,
                    tileZoom: tile.z
                )
            }

            if let normalizedRoadClass,
               let supplementalStyle = makeSupplementalRoadStyle(roadClass: normalizedRoadClass,
                                                                 tileZoom: tile.z,
                                                                 colors: colors) {
                return bridgeifyRoadStyleIfNeeded(
                    decorateRoadStyleIfNeeded(supplementalStyle,
                                              properties: properties,
                                              normalizedRoadClass: normalizedRoadClass,
                                              tileZoom: tile.z),
                    properties: properties,
                    tileZoom: tile.z
                )
            }

            return fallbackStyle

        case "building":
            return FeatureStyle(
                key: 210, // Topmost layer
                color: buildingFillColor,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0), // Filled polygon
                usesExtrusion: true,
                extrusionHeightScale: 8.0,
                extrusionAnchorZoom: 16
            )

        case "structure":
            if classValue?.lowercased() == "land", typeValue?.lowercased() == "bridge" {
                return FeatureStyle(
                    key: 36,
                    color: colors["background"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0),
                    linePlacement: .bridgeOverlay
                )
            }
            return fallbackStyle
            
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
                    key: 208,
                    color: colors["aeroway"]!,
                    parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 12)
                )
            }
            return FeatureStyle(
                key: 208,
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
