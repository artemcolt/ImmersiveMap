//
//  MVTTileParser.swift
//  TucikMap
//
//  Created by Artem on 5/28/25.
//

import Foundation
import MetalKit
internal import SwiftEarcut


class TileMvtParser {
    private static let dashEpsilon: Float = 0.0001
    private static let minClippedRoadLabelFragmentLength: Float = 256.0
    private static let houseNumberCollisionPriorityOffset: Int = 100_000
    private static let poiCollisionPriorityOffset: Int = 200_000
    let determineFeatureStyle               : DetermineFeatureStyle
    private let decodePolygon               : DecodePolygon = DecodePolygon()
    private let decodeLine                  : DecodeLine = DecodeLine()
    private let decodePoint                 : DecodePoint = DecodePoint()
    private let config                      : MapSettings
    private let labelTextResolver           : TileLabelTextResolver
    private let poiSpriteResolver           : PoiSpriteResolver = PoiSpriteResolver()
    private let crosswalkZebraBuilder       : CrosswalkZebraGeometryBuilder = CrosswalkZebraGeometryBuilder()
    private let roadDirectionArrowBuilder   : RoadDirectionArrowGeometryBuilder = RoadDirectionArrowGeometryBuilder()
    let tileExtent = Double(4096)

    
    init(determineFeatureStyle: DetermineFeatureStyle, config: MapSettings) {
        self.determineFeatureStyle = determineFeatureStyle
        self.config = config
        self.labelTextResolver = TileLabelTextResolver(config: config)
    }
    
    func parse(
        tile: Tile,
        mvtData: Data
    ) throws -> ParsedTile {
        let vectorTile = try VectorTile_Tile(serializedBytes: mvtData)
        let readingStageResult = readingStage(vectorTile: vectorTile, tile: tile)
        let unificationResult = unificationStage(readingStageResult: readingStageResult)
        
        return ParsedTile(
            drawingPolygon: unificationResult.drawingPolygon,
            drawingRoadPhases: unificationResult.drawingRoadPhases,
            drawingBridgePolygon: unificationResult.drawingBridgePolygon,
            drawingExtruded: unificationResult.drawingExtruded,
            styles: unificationResult.styles,
            overviewStyleMasks: unificationResult.overviewStyleMasks,
            bridgeStyles: unificationResult.bridgeStyles,
            bridgeOverviewStyleMasks: unificationResult.bridgeOverviewStyleMasks,
            tile: tile,
            textLabels: readingStageResult.textLabels,
            roadTextLabels: readingStageResult.roadTextLabels
        )
    }

    private func linePath(points: [SIMD2<Float>]) -> [SIMD2<Int16>] {
        points.map { point in
            let clampedX = min(max(point.x, 0.0), Float(tileExtent))
            let clampedY = min(max(point.y, 0.0), Float(tileExtent))
            return SIMD2(Int16(clamping: Int(clampedX.rounded())),
                         Int16(clamping: Int(clampedY.rounded())))
        }
    }

    private func isPointInsideTile(_ point: Point) -> Bool {
        point.x >= 0 &&
        point.x <= Int32(tileExtent) &&
        point.y >= 0 &&
        point.y <= Int32(tileExtent)
    }

    private func isPointStrictlyInsideTile(_ point: SIMD2<Float>) -> Bool {
        point.x > 0.0 &&
        point.x < Float(tileExtent) &&
        point.y > 0.0 &&
        point.y < Float(tileExtent)
    }

    private func isRoadBoundaryContinuationEndpoint(_ point: SIMD2<Float>?) -> Bool {
        guard let point else {
            return false
        }
        return LineClipper.isOnTileBoundary(point, tileExtent: Float(tileExtent))
    }

    private func shouldExtendRoadBoundaryEndpoint(_ point: SIMD2<Float>?) -> Bool {
        guard let point else {
            return false
        }

        let extent = Float(tileExtent)
        let epsilon: Float = 0.0001
        return abs(point.x - extent) <= epsilon || abs(point.y - extent) <= epsilon
    }

    private func shouldExtendClippedRoadEndpoint(_ point: SIMD2<Float>?) -> Bool {
        guard let point else {
            return false
        }

        let extent = Float(tileExtent)
        return point.x > extent || point.y > extent
    }

    private func roadStructureKind(attributes: [String: VectorTile_Tile.Value]) -> RoadStructureKind {
        let locationValue = attributes["location"]?.stringValue.lowercased() ?? ""
        let structureValue = attributes["structure"]?.stringValue.lowercased() ?? ""
        let brunnelValue = attributes["brunnel"]?.stringValue.lowercased() ?? ""
        let layerValue = attributes["layer"].flatMap(parseIntValue) ?? 0

        let isTunnel = isTruthy(attributes["underground"])
            || isTruthy(attributes["tunnel"])
            || locationValue.contains("underground")
            || locationValue.contains("subterranean")
            || locationValue.contains("tunnel")
            || locationValue.contains("underwater")
            || structureValue == "tunnel"
            || brunnelValue == "tunnel"
            || layerValue < 0
        if isTunnel {
            return .tunnel
        }

        let isBridge = isTruthy(attributes["bridge"])
            || structureValue == "bridge"
            || brunnelValue == "bridge"
            || locationValue.contains("bridge")
            || locationValue.contains("elevated")
            || layerValue > 0
        if isBridge {
            return .bridge
        }

        return .ground
    }

    private func roadLayerValue(attributes: [String: VectorTile_Tile.Value]) -> Int {
        attributes["layer"].flatMap(parseIntValue) ?? 0
    }

    private func buildHighZoomRoadSharedPointCounts(layer: VectorTile_Tile.Layer,
                                                    tile: Tile) -> [RoadConnectionPointKey: Int] {
        let lineClipper = LineClipper()
        var pointCounts: [RoadConnectionPointKey: Int] = [:]

        for feature in layer.features where feature.type == .linestring {
            let attributes = decodeAttributes(feature: feature, layer: layer)
            let style = determineFeatureStyle.makeStyle(data: DetFeatureStyleData(layerName: layer.name,
                                                                                  properties: attributes,
                                                                                  tile: tile))
            guard style.key != 0 else {
                continue
            }

            let lines = decodeLine.decode(geometry: feature.geometry)
            for line in lines {
                let fragments = lineClipper.clip(line: line, tileExtent: Float(tileExtent))
                for fragment in fragments {
                    for point in fragment.points {
                        pointCounts[RoadConnectionPointKey(point: point), default: 0] += 1
                    }
                }
            }
        }

        return pointCounts
    }

    private func lineLength(points: [SIMD2<Float>]) -> Float {
        guard points.count >= 2 else {
            return 0.0
        }

        var totalLength: Float = 0.0
        for index in 1..<points.count {
            totalLength += simd_length(points[index] - points[index - 1])
        }
        return totalLength
    }

    private func shouldIncludeRoadLabelFragment(_ fragment: ClippedLineFragment) -> Bool {
        guard fragment.points.count >= 2 else {
            return false
        }

        let isEdgeClipped = fragment.startClipped || fragment.endClipped
        guard isEdgeClipped else {
            return true
        }

        return lineLength(points: fragment.points) >= Self.minClippedRoadLabelFragmentLength
    }

    private func shouldRenderCrosswalkZebra(style: FeatureStyle,
                                            usesSeparateRoadRendering: Bool,
                                            roadStructure: RoadStructureKind) -> Bool {
        usesSeparateRoadRendering
        && style.roadDecorationKind == .zebraCrossing
        && roadStructure != .tunnel
    }

    private func renderFragments(for fragment: ClippedLineFragment,
                                 styleData: ParseGeometryStyleData) -> [ClippedLineFragment] {
        guard styleData.usesDashPattern else {
            return [fragment]
        }
        guard styleData.dashResetsPerSegment == false else {
            guard fragment.points.count >= 2 else {
                return [fragment]
            }

            var segmentedFragments: [ClippedLineFragment] = []
            segmentedFragments.reserveCapacity(fragment.points.count - 1)

            func direction(from start: SIMD2<Float>, to end: SIMD2<Float>) -> SIMD2<Float>? {
                let delta = end - start
                let length = simd_length(delta)
                guard length > Self.dashEpsilon else {
                    return nil
                }
                return delta / length
            }

            func isTurn(previous: SIMD2<Float>, current: SIMD2<Float>) -> Bool {
                let cross = previous.x * current.y - previous.y * current.x
                let dot = previous.x * current.x + previous.y * current.y
                return abs(cross) > 0.001 || dot < 0.999
            }

            let cornerInset = max(Float(styleData.lineWidth), Float(styleData.dashLength))
            for index in 0..<(fragment.points.count - 1) {
                let segmentStart = fragment.points[index]
                let segmentEnd = fragment.points[index + 1]
                guard let segmentDirection = direction(from: segmentStart, to: segmentEnd) else {
                    continue
                }

                var trimmedStart = segmentStart
                var trimmedEnd = segmentEnd

                if index > 0,
                   let previousDirection = direction(from: fragment.points[index - 1], to: segmentStart),
                   isTurn(previous: previousDirection, current: segmentDirection) {
                    trimmedStart += segmentDirection * cornerInset
                }

                if index < fragment.points.count - 2,
                   let nextDirection = direction(from: segmentEnd, to: fragment.points[index + 2]),
                   isTurn(previous: segmentDirection, current: nextDirection) {
                    trimmedEnd -= segmentDirection * cornerInset
                }

                if simd_length(trimmedEnd - trimmedStart) <= Self.dashEpsilon {
                    continue
                }

                segmentedFragments.append(contentsOf: centeredFullDashFragmentsForSegment(start: trimmedStart,
                                                                                          end: trimmedEnd,
                                                                                          dashLength: Float(styleData.dashLength),
                                                                                          dashGap: Float(styleData.dashGap)))
            }
            return segmentedFragments
        }
        return dashedFragments(from: fragment,
                               dashLength: Float(styleData.dashLength),
                               dashGap: Float(styleData.dashGap))
    }

    private func centeredFullDashFragmentsForSegment(start: SIMD2<Float>,
                                                     end: SIMD2<Float>,
                                                     dashLength: Float,
                                                     dashGap: Float) -> [ClippedLineFragment] {
        let delta = end - start
        let segmentLength = simd_length(delta)
        guard segmentLength > Self.dashEpsilon,
              dashLength > Self.dashEpsilon,
              dashGap > Self.dashEpsilon else {
            return []
        }

        let direction = delta / segmentLength
        let patternLength = dashLength + dashGap
        let dashCount = Int(((segmentLength + dashGap) / patternLength).rounded(.down))
        guard dashCount > 0 else {
            return []
        }

        let occupiedLength = Float(dashCount) * dashLength + Float(max(0, dashCount - 1)) * dashGap
        let leadingInset = max(0, (segmentLength - occupiedLength) * 0.5)
        let firstDashStart = start + direction * leadingInset

        var dashed: [ClippedLineFragment] = []
        dashed.reserveCapacity(dashCount)
        for index in 0..<dashCount {
            let offset = Float(index) * patternLength
            let dashStart = firstDashStart + direction * offset
            let dashEnd = dashStart + direction * dashLength
            dashed.append(ClippedLineFragment(points: [dashStart, dashEnd],
                                             startClipped: false,
                                             endClipped: false))
        }
        return dashed
    }

    private func dashedFragments(from fragment: ClippedLineFragment,
                                 dashLength: Float,
                                 dashGap: Float) -> [ClippedLineFragment] {
        guard fragment.points.count >= 2,
              dashLength > Self.dashEpsilon,
              dashGap > Self.dashEpsilon else {
            return [fragment]
        }

        var dashed: [ClippedLineFragment] = []
        var currentDashPoints: [SIMD2<Float>] = []
        currentDashPoints.reserveCapacity(fragment.points.count)

        var isDash = true
        var remainingPatternLength = dashLength
        var dashStartedAtFragmentStart = true

        func pointsEqual(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Bool {
            abs(lhs.x - rhs.x) <= Self.dashEpsilon && abs(lhs.y - rhs.y) <= Self.dashEpsilon
        }

        func appendPointIfNeeded(_ point: SIMD2<Float>) {
            if let last = currentDashPoints.last, pointsEqual(last, point) {
                return
            }
            currentDashPoints.append(point)
        }

        func finalizeDash(endedAtFragmentEnd: Bool) {
            guard currentDashPoints.count >= 2 else {
                currentDashPoints.removeAll(keepingCapacity: true)
                return
            }
            dashed.append(ClippedLineFragment(points: currentDashPoints,
                                             startClipped: dashStartedAtFragmentStart ? fragment.startClipped : false,
                                             endClipped: endedAtFragmentEnd ? fragment.endClipped : false))
            currentDashPoints.removeAll(keepingCapacity: true)
        }

        for index in 0..<(fragment.points.count - 1) {
            let segmentStart = fragment.points[index]
            let segmentEnd = fragment.points[index + 1]
            let segmentDelta = segmentEnd - segmentStart
            let segmentLength = simd_length(segmentDelta)
            guard segmentLength > Self.dashEpsilon else {
                continue
            }

            let direction = segmentDelta / segmentLength
            var currentPoint = segmentStart
            var remainingSegmentLength = segmentLength

            while remainingSegmentLength > Self.dashEpsilon {
                let traveledLength = min(remainingPatternLength, remainingSegmentLength)
                let nextPoint = currentPoint + direction * traveledLength
                let reachesFragmentEnd = index == fragment.points.count - 2
                    && remainingSegmentLength - traveledLength <= Self.dashEpsilon

                if isDash {
                    if currentDashPoints.isEmpty {
                        appendPointIfNeeded(currentPoint)
                    }
                    appendPointIfNeeded(nextPoint)
                }

                currentPoint = nextPoint
                remainingSegmentLength -= traveledLength
                remainingPatternLength -= traveledLength

                if remainingPatternLength <= Self.dashEpsilon {
                    if isDash {
                        finalizeDash(endedAtFragmentEnd: reachesFragmentEnd)
                    }
                    isDash.toggle()
                    remainingPatternLength = isDash ? dashLength : dashGap
                    dashStartedAtFragmentStart = false
                }
            }
        }

        if isDash, currentDashPoints.isEmpty == false {
            finalizeDash(endedAtFragmentEnd: true)
        }

        return dashed
    }

    private func labelSortKey(attributes: [String: VectorTile_Tile.Value]) -> Int {
        let classValue = attributes["class"]?.stringValue
        let typeValue = attributes["type"]?.stringValue
        let rankReferenceValue = typeValue ?? classValue

        let rankKeys = ["symbolrank", "sizerank", "filterrank", "rank", "scalerank", "place_rank", "localrank", "labelrank"]
        var baseRank: Int? = nil
        for key in rankKeys {
            if let value = attributes[key], let rank = parseIntValue(value) {
                baseRank = rank
                break
            }
        }

        let classRank = labelClassRank(rankReferenceValue)
        let rankValue = baseRank ?? classRank

        let classBias = labelClassBias(rankReferenceValue)

        let popKeys = ["population", "pop", "pop_max", "population_max", "pop_min", "population_min"]
        var population: Double = 0.0
        for key in popKeys {
            if let value = attributes[key], let pop = parseDoubleValue(value) {
                population = max(population, pop)
            }
        }
        let popBoost = population > 0.0 ? Int(min(90.0, log10(population) * 10.0)) : 0

        let isCapital = isTruthy(attributes["capital"])
        let capitalBoost = isCapital ? 30 : 0

        let sortKey = max(0, rankValue * 10 + classBias - popBoost - capitalBoost)
        return sortKey
    }

    private func pointLabelText(layerName: String,
                                attributes: [String: VectorTile_Tile.Value]) -> String? {
        if isHouseNumberPointLabelLayer(layerName.lowercased()) {
            return labelTextResolver.resolveHouseNumberText(attributes: attributes)
        }
        return labelTextResolver.resolveLabelText(attributes: attributes)
    }

    private func pointLabelCollisionPriority(layerName: String,
                                             sortKey: Int) -> Int {
        let normalizedLayerName = layerName.lowercased()
        if isHouseNumberPointLabelLayer(normalizedLayerName) {
            return Self.houseNumberCollisionPriorityOffset + sortKey
        }
        if normalizedLayerName == "poi_label" {
            return Self.poiCollisionPriorityOffset + sortKey
        }
        return sortKey
    }

    private func labelClassRank(_ classValue: String?) -> Int {
        guard let value = classValue?.lowercased() else {
            return 80
        }
        switch value {
        case "country":
            return 1
        case "state", "province", "region":
            return 5
        case "ocean":
            return 3
        case "sea":
            return 6
        case "settlement":
            return 12
        case "city":
            return 10
        case "town":
            return 20
        case "village":
            return 30
        case "hamlet":
            return 40
        case "settlement_subdivision":
            return 50
        case "suburb":
            return 50
        case "quarter":
            return 55
        case "neighborhood":
            return 60
        case "neighbourhood":
            return 60
        case "locality":
            return 70
        default:
            return 80
        }
    }

    private func labelClassBias(_ classValue: String?) -> Int {
        guard let value = classValue?.lowercased() else {
            return 9
        }
        switch value {
        case "country":
            return 0
        case "state", "province", "region":
            return 1
        case "ocean":
            return 1
        case "sea":
            return 2
        case "settlement":
            return 2
        case "city":
            return 2
        case "town":
            return 3
        case "village":
            return 4
        case "hamlet":
            return 5
        case "settlement_subdivision":
            return 6
        case "suburb":
            return 6
        case "quarter":
            return 6
        case "neighborhood":
            return 7
        case "neighbourhood":
            return 7
        case "locality":
            return 8
        default:
            return 9
        }
    }

    private func shouldIncludePointLabel(layerName: String,
                                         classValue: String?,
                                         typeValue: String?,
                                         attributes: [String: VectorTile_Tile.Value],
                                         sortKey: Int,
                                         tileZoom: Int) -> Bool {
        let normalizedLayerName = layerName.lowercased()

        if isRoadPointLabelLayer(normalizedLayerName) || isTransitPointLabelLayer(normalizedLayerName) {
            return false
        }

        if isHouseNumberPointLabelLayer(normalizedLayerName) {
            guard config.labels.houseNumbers.enabled else {
                return false
            }
            return tileZoom >= config.labels.houseNumbers.minimumZoom
        }

        if isContinentPointLabel(layerName: normalizedLayerName,
                                 classValue: classValue,
                                 typeValue: typeValue) {
            guard tileZoom <= 2 else {
                return false
            }
            return true
        }

        if isOceanPointLabel(layerName: normalizedLayerName,
                             classValue: classValue,
                             typeValue: typeValue) {
            guard tileZoom <= 2 else {
                return false
            }
            return true
        }

        if hasCapitalPriority(attributes: attributes) {
            guard tileZoom >= 2,
                  tileZoom <= config.labels.settlementVisibility.capitalMaximumZoom else {
                return false
            }
            return true
        }

        if normalizedLayerName == "poi_label" {
            if isLandmarkPointLabel(layerName: normalizedLayerName,
                                    classValue: classValue,
                                    typeValue: typeValue) {
                guard tileZoom >= config.labels.landmarks.minimumZoom else {
                    return false
                }
                return sortKey <= landmarkSortKeyThreshold(for: tileZoom)
            }

            guard tileZoom >= 13 else {
                return false
            }
            return sortKey <= poiSortKeyThreshold(for: tileZoom)
        }

        if isAirportPointLabelLayer(normalizedLayerName) {
            guard tileZoom >= 8 else {
                return false
            }
            return sortKey <= airportSortKeyThreshold(for: tileZoom)
        }

        if isNaturalPointLabel(layerName: normalizedLayerName, classValue: classValue) {
            guard tileZoom >= 9 else {
                return false
            }
            return sortKey <= naturalSortKeyThreshold(for: tileZoom)
        }

        if isLandmarkPointLabel(layerName: normalizedLayerName,
                                classValue: classValue,
                                typeValue: typeValue) {
            guard tileZoom >= config.labels.landmarks.minimumZoom else {
                return false
            }
            return sortKey <= landmarkSortKeyThreshold(for: tileZoom)
        }

        if isCityPointLabel(classValue: classValue, typeValue: typeValue) {
            guard tileZoom >= 2,
                  tileZoom <= config.labels.settlementVisibility.cityMaximumZoom else {
                return false
            }
            return sortKey <= citySortKeyThreshold(for: tileZoom)
        }

        if isDistrictPointLabel(classValue: classValue, typeValue: typeValue) {
            guard tileZoom >= 9 else {
                return false
            }
            return sortKey <= districtSortKeyThreshold(for: tileZoom)
        }

        if isSmallSettlementPointLabel(typeValue: typeValue) {
            guard tileZoom >= 10,
                  tileZoom <= config.labels.settlementVisibility.smallSettlementMaximumZoom else {
                return false
            }
            return sortKey <= smallSettlementSortKeyThreshold(for: tileZoom)
        }

        return true
    }

    private func hasCapitalPriority(attributes: [String: VectorTile_Tile.Value]) -> Bool {
        if let capitalValue = attributes["capital"] {
            if let capitalLevel = parseIntValue(capitalValue), capitalLevel > 0 {
                return true
            }
            if isTruthy(capitalValue) {
                return true
            }
        }
        return false
    }

    private func isRoadPointLabelLayer(_ layerName: String) -> Bool {
        layerName == "road_label"
    }

    private func isHouseNumberPointLabelLayer(_ layerName: String) -> Bool {
        layerName == "housenum_label"
    }

    private func isTransitPointLabelLayer(_ layerName: String) -> Bool {
        layerName.contains("transit")
    }

    private func isAirportPointLabelLayer(_ layerName: String) -> Bool {
        layerName == "airport_label"
    }

    private func isLandmarkPointLabel(layerName: String,
                                      classValue: String?,
                                      typeValue: String?) -> Bool {
        let normalizedValues = [typeValue, classValue].compactMap(normalizeLandmarkValue)
        guard normalizedValues.isEmpty == false else {
            return false
        }

        for value in normalizedValues {
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
                continue
            }
        }
        return false
    }

    private func normalizeLandmarkValue(_ value: String?) -> String? {
        value?
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func isContinentPointLabel(layerName: String,
                                       classValue: String?,
                                       typeValue: String?) -> Bool {
        guard layerName == "natural_label" else {
            return false
        }

        let normalizedValues = [typeValue?.lowercased(), classValue?.lowercased()].compactMap { $0 }
        return normalizedValues.contains("continent")
    }

    private func isOceanPointLabel(layerName: String,
                                   classValue: String?,
                                   typeValue: String?) -> Bool {
        guard layerName == "natural_label" else {
            return false
        }

        let normalizedValues = [typeValue?.lowercased(), classValue?.lowercased()].compactMap { $0 }
        return normalizedValues.contains("ocean") || normalizedValues.contains("sea")
    }

    private func isDistrictPointLabel(classValue: String?, typeValue: String?) -> Bool {
        if classValue?.lowercased() == "settlement_subdivision" {
            return true
        }
        guard let value = typeValue?.lowercased() else {
            return false
        }
        switch value {
        case "suburb",
             "quarter",
             "neighborhood",
             "neighbourhood",
             "locality",
             "borough",
             "district":
            return true
        default:
            return false
        }
    }

    private func isCityPointLabel(classValue: String?, typeValue: String?) -> Bool {
        guard let typeValue = typeValue?.lowercased() else {
            return classValue?.lowercased() == "settlement"
        }
        return typeValue == "city"
    }

    private func isNaturalPointLabel(layerName: String, classValue: String?) -> Bool {
        guard layerName == "natural_label" else {
            return false
        }

        switch classValue?.lowercased() {
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

    private func isSmallSettlementPointLabel(typeValue: String?) -> Bool {
        guard let value = typeValue?.lowercased() else {
            return false
        }

        switch value {
        case "town",
             "village",
             "hamlet",
             "isolated_dwelling":
            return true
        default:
            return false
        }
    }

    private func landmarkSortKeyThreshold(for tileZoom: Int) -> Int {
        switch tileZoom {
        case 9:
            return 70
        case 10:
            return 90
        case 11:
            return 110
        case 12:
            return 130
        case 13:
            return 150
        case 14:
            return 170
        default:
            return 200
        }
    }

    private func airportSortKeyThreshold(for tileZoom: Int) -> Int {
        switch tileZoom {
        case 8:
            return 55
        case 9:
            return 75
        case 10...11:
            return 95
        default:
            return 115
        }
    }

    private func naturalSortKeyThreshold(for tileZoom: Int) -> Int {
        switch tileZoom {
        case 9:
            return 70
        case 10:
            return 90
        case 11...12:
            return 110
        default:
            return 130
        }
    }

    private func districtSortKeyThreshold(for tileZoom: Int) -> Int {
        switch tileZoom {
        case 9:
            return 150
        case 10:
            return 160
        case 11:
            return 210
        case 12:
            return 245
        case 13:
            return 280
        case 14:
            return 320
        case 15:
            return 360
        default:
            return 400
        }
    }

    private func citySortKeyThreshold(for tileZoom: Int) -> Int {
        switch tileZoom {
        case 2:
            return 80
        case 3:
            return 90
        case 4:
            return 95
        case 5:
            return 100
        case 6:
            return 105
        case 7:
            return 110
        case 8:
            return 115
        case 9:
            return 120
        case 10:
            return 145
        case 11:
            return 185
        case 12:
            return 225
        case 13:
            return 255
        case 14:
            return 285
        case 15:
            return 315
        default:
            return 345
        }
    }

    private func smallSettlementSortKeyThreshold(for tileZoom: Int) -> Int {
        switch tileZoom {
        case 10:
            return 180
        case 11:
            return 220
        case 12:
            return 260
        case 13...14:
            return 320
        default:
            return 380
        }
    }

    private func poiSortKeyThreshold(for tileZoom: Int) -> Int {
        switch tileZoom {
        case 13:
            return 60
        case 14:
            return 90
        case 15:
            return 130
        default:
            return 170
        }
    }

    private func fallbackLowZoomWaterLabels(for tile: Tile) -> [(name: String, latitude: Double, longitude: Double, sortKey: Int, styleClass: String)] {
        let language = config.labels.language

        func localized(_ english: String, russian: String) -> String {
            switch language {
            case .english:
                return english
            case .russian:
                return russian
            }
        }

        var labels: [(name: String, latitude: Double, longitude: Double, sortKey: Int, styleClass: String)] = [
            (localized("Pacific Ocean", russian: "Тихий океан"), 0.0, -150.0, 20, "ocean"),
            (localized("Atlantic Ocean", russian: "Атлантический океан"), 8.0, -32.0, 18, "ocean"),
            (localized("Indian Ocean", russian: "Индийский океан"), -18.0, 80.0, 22, "ocean"),
            (localized("Arctic Ocean", russian: "Северный Ледовитый океан"), 76.0, 15.0, 16, "ocean"),
            (localized("Southern Ocean", russian: "Южный океан"), -56.0, 25.0, 24, "ocean")
        ]

        if tile.z == 2 {
            labels.append((localized("Mediterranean Sea", russian: "Средиземное море"), 35.0, 18.0, 30, "sea"))
            labels.append((localized("Caribbean Sea", russian: "Карибское море"), 15.0, -74.0, 32, "sea"))
            labels.append((localized("Arabian Sea", russian: "Аравийское море"), 15.0, 64.0, 34, "sea"))
            labels.append((localized("Bering Sea", russian: "Берингово море"), 57.0, -178.0, 36, "sea"))
        }

        return labels
    }

    private func stringTileValue(_ value: String) -> VectorTile_Tile.Value {
        var tileValue = VectorTile_Tile.Value()
        tileValue.stringValue = value
        return tileValue
    }

    private func tilePoint(forLatitude latitude: Double,
                           longitude: Double,
                           tile: Tile) -> SIMD2<Int16>? {
        let n = pow(2.0, Double(tile.z))
        guard n > 0 else { return nil }

        let wrappedLongitude = ((longitude + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0) - 180.0
        let x = (wrappedLongitude + 180.0) / 360.0 * n

        let clampedLatitude = min(max(latitude, -85.05112878), 85.05112878)
        let latitudeRadians = clampedLatitude * .pi / 180.0
        let y = (1.0 - log(tan(latitudeRadians) + 1.0 / cos(latitudeRadians)) / .pi) * 0.5 * n

        let localX = (x - Double(tile.x)) * 4096.0
        let localY = (y - Double(tile.y)) * 4096.0
        guard localX >= 0.0, localX <= 4096.0, localY >= 0.0, localY <= 4096.0 else {
            return nil
        }

        let roundedX = Int16(max(0, min(4096, Int(localX.rounded()))))
        let roundedY = Int16(max(0, min(4096, Int(localY.rounded()))))
        return SIMD2<Int16>(roundedX, roundedY)
    }

    private func appendFallbackLowZoomWaterLabels(into textLabels: inout [TextLabel], tile: Tile) {
        guard tile.z <= 2 else {
            return
        }

        let existingWaterText = Set(
            textLabels.filter { $0.textStyle.key == 3 || $0.textStyle.key == 4 }
                .map(\.text)
        )

        for fallback in fallbackLowZoomWaterLabels(for: tile) {
            guard existingWaterText.contains(fallback.name) == false,
                  let point = tilePoint(forLatitude: fallback.latitude,
                                        longitude: fallback.longitude,
                                        tile: tile) else {
                continue
            }

            let attributes: [String: VectorTile_Tile.Value] = [
                "class": stringTileValue(fallback.styleClass),
                "type": stringTileValue(fallback.styleClass),
                "name": stringTileValue(fallback.name)
            ]

            let style = determineFeatureStyle.makeStyle(data: DetFeatureStyleData(layerName: "natural_label",
                                                                                  properties: attributes,
                                                                                  tile: tile))
            guard let textStyle = style.labelTextStyle else {
                continue
            }

            textLabels.append(TextLabel(text: fallback.name,
                                        position: point,
                                        tile: tile,
                                        featureId: 0,
                                        hasFeatureId: false,
                                        layerName: "natural_label",
                                        sortKey: fallback.sortKey,
                                        collisionPriority: fallback.sortKey,
                                        textStyle: textStyle,
                                        poiIcon: nil))
        }
    }

    
    func readingStage(vectorTile: VectorTile_Tile, tile: Tile) -> ReadingStageResult {
        let parsePolygon = ParsePolygon()
        let parseLine = ParseLine()
        let lineClipper = LineClipper()
        var polygonByStyle: [UInt8: [ParsedPolygon]] = [:]
        var roadPolygonByStyle: [UInt8: [ParsedPolygon]] = [:]
        var orderedRoadPolygons: [OrderedRoadPolygon] = []
        var bridgePolygonByStyle: [UInt8: [ParsedPolygon]] = [:]
        let rawLineByStyle: [UInt8: [ParsedLineRawVertices]] = [:]
        var extrudedByStyle: [UInt8: [ParsedExtrudedMesh]] = [:]
        var styles: [UInt8: FeatureStyle] = [:]
        var roadStyles: [UInt8: FeatureStyle] = [:]
        var bridgeStyles: [UInt8: FeatureStyle] = [:]
        var textLabels: [TextLabel] = []
        var roadTextLabels: [RoadTextLabel] = []
        var roadPolygonSequence = 0
        var buildingExtrusionCandidates: [BuildingExtrusionCandidate] = []
        
        for layer in vectorTile.layers {
            let layerName = layer.name
            let buildingPartIds = layerName == "building" ? collectBuildingPartIds(layer: layer) : []
            let buildingPartFootprintSignatures = layerName == "building"
                ? collectBuildingPartFootprintSignatures(layer: layer)
                : []
            let highZoomRoadSharedPointCounts = layerName == "road"
                && tile.z >= config.style.flatSeparateRoadRenderingMinimumZoom
                ? buildHighZoomRoadSharedPointCounts(layer: layer, tile: tile)
                : [:]
            for feature in layer.features {
                let attributes = decodeAttributes(feature: feature, layer: layer)
                
                let detStyleData = DetFeatureStyleData(
                    layerName: layerName,
                    properties: attributes,
                    tile: tile
                )
                let usesSeparateRoadRendering = layerName == "road"
                    && tile.z >= config.style.flatSeparateRoadRenderingMinimumZoom

                let style = determineFeatureStyle.makeStyle(data: detStyleData)
                let styleKey = style.key
                if styleKey == 0 {
                    // none defineded style
                    continue
                }
                if feature.type != .linestring || usesSeparateRoadRendering == false {
                    switch style.linePlacement {
                    case .ground:
                        if styles[styleKey] == nil {
                            styles[styleKey] = style
                        }
                    case .bridgeOverlay:
                        if bridgeStyles[styleKey] == nil {
                            bridgeStyles[styleKey] = style
                        }
                    }
                }
                
                
                if feature.type == .polygon {
                    let geometry: [UInt32] = feature.geometry
                    let polygons = decodePolygon.decode(geometry: geometry)
                    let extrudeFlag = attributes["extrude"].flatMap(parseBoolValue)
                    let isBuildingPart = isTruthy(attributes["building:part"])
                    let buildingId = buildingIdentifier(attributes: attributes, featureId: feature.id)
                    let hasParts = buildingPartIds.contains(buildingId)
                    let matchesPartFootprint = isBuildingPart == false
                        && polygons.contains { polygon in
                            guard let signature = buildingFootprintSignature(for: polygon) else {
                                return false
                            }
                            return buildingPartFootprintSignatures.contains(signature)
                        }
                    let locationValue = attributes["location"]?.stringValue.lowercased() ?? ""
                    let isUnderground = isTruthy(attributes["underground"])
                        || locationValue.contains("underground")
                        || locationValue.contains("subterranean")
                        || locationValue.contains("tunnel")
                        || locationValue.contains("underwater")
                    let shouldExtrude = style.usesExtrusion
                        && (extrudeFlag == true)
                        && !isUnderground
                        && !matchesPartFootprint
                        && !(hasParts && !isBuildingPart)
                    let extrusion = shouldExtrude
                        ? extrusionHeights(attributes: attributes, tileZoom: tile.z, style: style)
                        : nil
                    
                    for polygon in polygons {
                        guard let parsedGeometry = parsePolygon.parseGeometry(polygon: polygon,
                                                                              tileExtent: Float(tileExtent)) else {
                            continue
                        }
                        switch style.linePlacement {
                        case .ground:
                            polygonByStyle[styleKey, default: []].append(parsedGeometry.parsedPolygon)
                        case .bridgeOverlay:
                            bridgePolygonByStyle[styleKey, default: []].append(parsedGeometry.parsedPolygon)
                        }
                        
                        if let extrusion,
                           extrusion.top > extrusion.base,
                           let footprintSignature = buildingFootprintSignature(for: polygon) {
                            buildingExtrusionCandidates.append(
                                BuildingExtrusionCandidate(styleKey: styleKey,
                                                           buildingId: buildingId,
                                                           footprintSignature: footprintSignature,
                                                           clippedExterior: parsedGeometry.clipped.exterior,
                                                           clippedInteriors: parsedGeometry.clipped.interiors,
                                                           roof: parsedGeometry.parsedPolygon,
                                                           roofInfo: extrusion.roof,
                                                           baseHeight: extrusion.base,
                                                           topHeight: extrusion.top)
                            )
                        }
                    }
                    
                } else if feature.type == .linestring {
                    let geometry: [UInt32] = feature.geometry
                    let lineRenderPasses = style.resolvedLineRenderPasses.filter { $0.parseGeometryStyleData.lineWidth > 0 }
                    if lineRenderPasses.isEmpty {
                        continue
                    }

                    let labelText = labelTextResolver.resolveLabelText(attributes: attributes)
                    let roadLabelPass = lineRenderPasses.first { $0.includeRoadLabelPath }
                    let roadLabelStyle = style.roadLabelTextStyle
                    let roadStructure = roadStructureKind(attributes: attributes)
                    let roadLayer = roadLayerValue(attributes: attributes)
                    let roadClassPriority = style.roadClassPriority
                    let sharedRoadPadding = Float(
                        lineRenderPasses.reduce(0.0) { partial, pass in
                            max(partial, pass.parseGeometryStyleData.lineWidth * 0.5)
                        }
                    )
                    let lines = decodeLine.decode(geometry: geometry)
                    for line in lines {
                        let exactClippedFragments = lineClipper.clip(line: line, tileExtent: Float(tileExtent))
                        guard exactClippedFragments.isEmpty == false else {
                            continue
                        }
                        let sharedPaddedFragments = usesSeparateRoadRendering
                            ? lineClipper.clip(line: line,
                                               tileExtent: Float(tileExtent),
                                               padding: sharedRoadPadding)
                            : []

                        for lineRenderPass in lineRenderPasses {
                            if style.roadDecorationKind == .zebraCrossing, roadStructure == .tunnel {
                                continue
                            }

                            let passStyle = FeatureStyle(
                                key: lineRenderPass.key,
                                color: lineRenderPass.color,
                                lowZoomFadeMask: lineRenderPass.lowZoomFadeMask,
                                parseGeometryStyleData: lineRenderPass.parseGeometryStyleData,
                                includeRoadLabelPath: lineRenderPass.includeRoadLabelPath,
                                linePlacement: lineRenderPass.placement,
                                roadClassPriority: roadClassPriority,
                                roadLabelTextStyle: roadLabelStyle,
                                roadDecorationKind: style.roadDecorationKind
                            )
                            if usesSeparateRoadRendering {
                                if roadStyles[lineRenderPass.key] == nil {
                                    roadStyles[lineRenderPass.key] = passStyle
                                }
                            } else {
                                switch lineRenderPass.placement {
                                case .ground:
                                    if styles[lineRenderPass.key] == nil {
                                        styles[lineRenderPass.key] = passStyle
                                    }
                                case .bridgeOverlay:
                                    if bridgeStyles[lineRenderPass.key] == nil {
                                        bridgeStyles[lineRenderPass.key] = passStyle
                                    }
                                }
                            }

                            if shouldRenderCrosswalkZebra(style: style,
                                                          usesSeparateRoadRendering: usesSeparateRoadRendering,
                                                          roadStructure: roadStructure) {
                                for fragment in exactClippedFragments {
                                    let zebraPolygons = crosswalkZebraBuilder.buildPolygons(
                                        points: fragment.points,
                                        zoneWidth: Float(lineRenderPass.parseGeometryStyleData.lineWidth),
                                        tileExtent: Float(tileExtent)
                                    )
                                    for zebraPolygon in zebraPolygons {
                                        roadPolygonByStyle[lineRenderPass.key, default: []].append(zebraPolygon)
                                        orderedRoadPolygons.append(
                                            OrderedRoadPolygon(
                                                polygon: zebraPolygon,
                                                styleKey: lineRenderPass.key,
                                                structureKind: roadStructure,
                                                layer: roadLayer,
                                                classPriority: roadClassPriority,
                                                passRole: lineRenderPass.roadPassRole,
                                                sequence: roadPolygonSequence
                                            )
                                        )
                                        roadPolygonSequence += 1
                                    }
                                }
                                continue
                            }

                            if usesSeparateRoadRendering,
                               style.roadDecorationKind == .onewayArrow,
                               lineRenderPass.roadPassRole == .detail {
                                for fragment in exactClippedFragments {
                                    let arrowPolygons = roadDirectionArrowBuilder.buildPolygons(
                                        points: fragment.points,
                                        lineWidth: Float(lineRenderPass.parseGeometryStyleData.lineWidth),
                                        tileExtent: Float(tileExtent)
                                    )
                                    for arrowPolygon in arrowPolygons {
                                        roadPolygonByStyle[lineRenderPass.key, default: []].append(arrowPolygon)
                                        orderedRoadPolygons.append(
                                            OrderedRoadPolygon(
                                                polygon: arrowPolygon,
                                                styleKey: lineRenderPass.key,
                                                structureKind: roadStructure,
                                                layer: roadLayer,
                                                classPriority: roadClassPriority,
                                                passRole: lineRenderPass.roadPassRole,
                                                sequence: roadPolygonSequence
                                            )
                                        )
                                        roadPolygonSequence += 1
                                    }
                                }
                                continue
                            }

                            let padding = Float(lineRenderPass.parseGeometryStyleData.lineWidth * 0.5)
                            let paddedFragments = usesSeparateRoadRendering
                                ? sharedPaddedFragments
                                : lineClipper.clip(line: line,
                                                   tileExtent: Float(tileExtent),
                                                   padding: padding)

                            for fragment in paddedFragments {
                                let renderFragments = renderFragments(for: fragment,
                                                                      styleData: lineRenderPass.parseGeometryStyleData)

                                for renderFragment in renderFragments {
                                    let startConnected = usesSeparateRoadRendering
                                        && renderFragment.points.first.map {
                                            (highZoomRoadSharedPointCounts[RoadConnectionPointKey(point: $0)] ?? 0) > 1
                                        } == true
                                    let endConnected = usesSeparateRoadRendering
                                        && renderFragment.points.last.map {
                                            (highZoomRoadSharedPointCounts[RoadConnectionPointKey(point: $0)] ?? 0) > 1
                                        } == true
                                    let startBoundaryContinuation = usesSeparateRoadRendering
                                        && isRoadBoundaryContinuationEndpoint(renderFragment.points.first)
                                    let endBoundaryContinuation = usesSeparateRoadRendering
                                        && isRoadBoundaryContinuationEndpoint(renderFragment.points.last)
                                    let startContinuation = usesSeparateRoadRendering
                                        && (renderFragment.startClipped || startBoundaryContinuation)
                                    let endContinuation = usesSeparateRoadRendering
                                        && (renderFragment.endClipped || endBoundaryContinuation)
                                    let shouldExtendStart = usesSeparateRoadRendering
                                        && ((renderFragment.startClipped && shouldExtendClippedRoadEndpoint(renderFragment.points.first))
                                            || (startBoundaryContinuation && shouldExtendRoadBoundaryEndpoint(renderFragment.points.first)))
                                    let shouldExtendEnd = usesSeparateRoadRendering
                                        && ((renderFragment.endClipped && shouldExtendClippedRoadEndpoint(renderFragment.points.last))
                                            || (endBoundaryContinuation && shouldExtendRoadBoundaryEndpoint(renderFragment.points.last)))

                                    let startCapRound = lineRenderPass.parseGeometryStyleData.lineCapRound
                                        && startContinuation == false
                                        && startConnected == false
                                        && renderFragment.points.first.map { isPointStrictlyInsideTile($0) } == true
                                    let endCapRound = lineRenderPass.parseGeometryStyleData.lineCapRound
                                        && endContinuation == false
                                        && endConnected == false
                                        && renderFragment.points.last.map { isPointStrictlyInsideTile($0) } == true

                                    if let linePolygon = parseLine.parse(points: renderFragment.points,
                                                                         width: lineRenderPass.parseGeometryStyleData.lineWidth,
                                                                         tileExtent: Float(tileExtent),
                                                                         startCapRound: startCapRound,
                                                                         endCapRound: endCapRound,
                                                                         lineJoinRound: lineRenderPass.parseGeometryStyleData.lineJoinRound,
                                                                         extendClippedStart: shouldExtendStart,
                                                                         extendClippedEnd: shouldExtendEnd,
                                                                         clipPadding: usesSeparateRoadRendering ? sharedRoadPadding : 0,
                                                                         clipGeometryToTileBounds: usesSeparateRoadRendering == false) {
                                        if usesSeparateRoadRendering {
                                            roadPolygonByStyle[lineRenderPass.key, default: []].append(linePolygon)
                                            orderedRoadPolygons.append(
                                                OrderedRoadPolygon(
                                                    polygon: linePolygon,
                                                    styleKey: lineRenderPass.key,
                                                    structureKind: roadStructure,
                                                    layer: roadLayer,
                                                    classPriority: roadClassPriority,
                                                    passRole: lineRenderPass.roadPassRole,
                                                    sequence: roadPolygonSequence
                                                )
                                            )
                                            roadPolygonSequence += 1
                                        } else {
                                            switch lineRenderPass.placement {
                                            case .ground:
                                                polygonByStyle[lineRenderPass.key, default: []].append(linePolygon)
                                            case .bridgeOverlay:
                                                bridgePolygonByStyle[lineRenderPass.key, default: []].append(linePolygon)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if roadLabelPass != nil,
                           let labelText,
                           let roadLabelStyle {
                            for fragment in exactClippedFragments {
                                guard shouldIncludeRoadLabelFragment(fragment) else {
                                    continue
                                }
                                let path = linePath(points: fragment.points)
                                if path.count >= 2 {
                                    roadTextLabels.append(RoadTextLabel(text: labelText,
                                                                        path: path,
                                                                        tile: tile,
                                                                        featureId: feature.id,
                                                                        hasFeatureId: feature.hasID,
                                                                        layerName: layerName,
                                                                        textStyle: roadLabelStyle))
                                }
                            }
                        }
                    }
                } else if feature.type == .point {
                    guard let labelText = pointLabelText(layerName: layerName, attributes: attributes) else { continue }
                    guard let labelTextStyle = style.labelTextStyle else { continue }
                    let points = decodePoint.decode(geometry: feature.geometry)
                    let featureId = feature.id
                    let sortKey = labelSortKey(attributes: attributes)
                    let collisionPriority = pointLabelCollisionPriority(layerName: layerName, sortKey: sortKey)
                    let classValue = attributes["class"]?.stringValue
                    let typeValue = attributes["type"]?.stringValue
                    let poiIcon = poiSpriteResolver.resolve(attributes: attributes, layerName: layerName)
                    guard shouldIncludePointLabel(layerName: layerName,
                                                  classValue: classValue,
                                                  typeValue: typeValue,
                                                  attributes: attributes,
                                                  sortKey: sortKey,
                                                  tileZoom: tile.z) else {
                        continue
                    }
                    for point in points where isPointInsideTile(point) {
                        textLabels.append(TextLabel(text: labelText,
                                                    position: SIMD2(Int16(point.x), Int16(point.y)),
                                                    tile: tile,
                                                    featureId: featureId,
                                                    hasFeatureId: feature.hasID,
                                                    layerName: layerName,
                                                    sortKey: sortKey,
                                                    collisionPriority: collisionPriority,
                                                    textStyle: labelTextStyle,
                                                    poiIcon: poiIcon))
                    }
                }
            }

        }

        appendFallbackLowZoomWaterLabels(into: &textLabels, tile: tile)
        
        addBackground(polygonByStyle: &polygonByStyle, styles: &styles)
        if config.tiles.parsing.addTestBorders { addBorder(polygonByStyle: &polygonByStyle, styles: &styles, borderWidth: 1) }

        let resolvedBuildingExtrusions = resolveExteriorBuildingExtrusions(buildingExtrusionCandidates)
        for candidate in resolvedBuildingExtrusions {
            if let extrudedMesh = buildExtrudedMesh(clippedExterior: candidate.clippedExterior,
                                                    clippedInteriors: candidate.clippedInteriors,
                                                    roof: candidate.roof,
                                                    roofInfo: candidate.roofInfo,
                                                    baseHeight: candidate.baseHeight,
                                                    topHeight: candidate.topHeight,
                                                    tileExtent: Float(tileExtent)) {
                extrudedByStyle[candidate.styleKey, default: []].append(extrudedMesh)
            }
        }
        
        return ReadingStageResult(
            polygonByStyle: polygonByStyle.filter { $0.value.isEmpty == false },
            roadPolygonByStyle: roadPolygonByStyle.filter { $0.value.isEmpty == false },
            orderedRoadPolygons: orderedRoadPolygons,
            bridgePolygonByStyle: bridgePolygonByStyle.filter { $0.value.isEmpty == false },
            rawLineByStyle: rawLineByStyle.filter { $0.value.isEmpty == false },
            extrudedByStyle: extrudedByStyle.filter { $0.value.isEmpty == false },
            styles: styles,
            roadStyles: roadStyles,
            bridgeStyles: bridgeStyles,
            textLabels: textLabels,
            roadTextLabels: roadTextLabels
        )
    }

    private func unifyPolygonLayer(polygonByStyle: [UInt8: [ParsedPolygon]],
                                   stylesByKey: [UInt8: FeatureStyle]) -> (drawing: DrawingPolygonBytes,
                                                                           styles: [TilePolygonStyle],
                                                                           overviewStyleMasks: [Float]) {
        var unifiedVertices: [TilePipeline.VertexIn] = []
        var unifiedIndices: [UInt32] = []
        var currentVertexOffset: UInt32 = 0
        var styles: [TilePolygonStyle] = []
        var overviewStyleMasks: [Float] = []

        let totalPolygonVertexCount = polygonByStyle.values.reduce(0) { partial, polygons in
            partial + polygons.reduce(0) { polygonPartial, polygon in
                polygonPartial + polygon.vertices.count
            }
        }
        let totalPolygonIndexCount = polygonByStyle.values.reduce(0) { partial, polygons in
            partial + polygons.reduce(0) { polygonPartial, polygon in
                polygonPartial + polygon.indices.count
            }
        }

        unifiedVertices.reserveCapacity(totalPolygonVertexCount)
        unifiedIndices.reserveCapacity(totalPolygonIndexCount)

        let styleKeys = polygonByStyle.keys
            .filter { polygonByStyle[$0]?.isEmpty == false }
            .sorted()
        var styleIndexByKey: [UInt8: UInt8] = [:]
        styleIndexByKey.reserveCapacity(styleKeys.count)
        styles.reserveCapacity(styleKeys.count)
        overviewStyleMasks.reserveCapacity(styleKeys.count)
        for (index, styleKey) in styleKeys.enumerated() {
            if index > Int(UInt8.max) {
                assertionFailure("Too many styles for tile pipeline.")
                continue
            }
            styleIndexByKey[styleKey] = UInt8(index)
        }

        for styleKey in styleKeys {
            let styleBufferIndex = styleIndexByKey[styleKey] ?? 0
            if let polygons = polygonByStyle[styleKey] {
                for polygon in polygons {
                    for position in polygon.vertices {
                        unifiedVertices.append(TilePipeline.VertexIn(position: position, styleIndex: styleBufferIndex))
                    }
                    for index in polygon.indices {
                        unifiedIndices.append(index + currentVertexOffset)
                    }
                    currentVertexOffset += UInt32(polygon.vertices.count)
                }
            }

            if let style = stylesByKey[styleKey] {
                styles.append(TilePolygonStyle(color: style.color))
                overviewStyleMasks.append(style.lowZoomFadeMask)
            }
        }

        return (drawing: DrawingPolygonBytes(vertices: unifiedVertices,
                                             indices: unifiedIndices),
                styles: styles,
                overviewStyleMasks: overviewStyleMasks)
    }

    private func unifyOrderedRoadLayer(orderedRoadPolygons: [OrderedRoadPolygon],
                                       stylesByKey: [UInt8: FeatureStyle]) -> (drawing: DrawingPolygonBytes,
                                                                               styles: [TilePolygonStyle],
                                                                               overviewStyleMasks: [Float]) {
        var unifiedVertices: [TilePipeline.VertexIn] = []
        var unifiedIndices: [UInt32] = []
        var currentVertexOffset: UInt32 = 0
        var styles: [TilePolygonStyle] = []
        var overviewStyleMasks: [Float] = []

        let totalPolygonVertexCount = orderedRoadPolygons.reduce(0) { partial, polygon in
            partial + polygon.polygon.vertices.count
        }
        let totalPolygonIndexCount = orderedRoadPolygons.reduce(0) { partial, polygon in
            partial + polygon.polygon.indices.count
        }

        unifiedVertices.reserveCapacity(totalPolygonVertexCount)
        unifiedIndices.reserveCapacity(totalPolygonIndexCount)

        let styleKeys = Array(Set(orderedRoadPolygons.map(\.styleKey))).sorted()
        var styleIndexByKey: [UInt8: UInt8] = [:]
        styleIndexByKey.reserveCapacity(styleKeys.count)
        styles.reserveCapacity(styleKeys.count)
        overviewStyleMasks.reserveCapacity(styleKeys.count)

        for (index, styleKey) in styleKeys.enumerated() {
            if index > Int(UInt8.max) {
                assertionFailure("Too many styles for tile pipeline.")
                continue
            }
            styleIndexByKey[styleKey] = UInt8(index)
            if let style = stylesByKey[styleKey] {
                styles.append(TilePolygonStyle(color: style.color))
                overviewStyleMasks.append(style.lowZoomFadeMask)
            }
        }

        for orderedPolygon in orderedRoadPolygons.sorted(by: OrderedRoadPolygon.sort) {
            let styleBufferIndex = styleIndexByKey[orderedPolygon.styleKey] ?? 0
            for position in orderedPolygon.polygon.vertices {
                unifiedVertices.append(TilePipeline.VertexIn(position: position, styleIndex: styleBufferIndex))
            }
            for index in orderedPolygon.polygon.indices {
                unifiedIndices.append(index + currentVertexOffset)
            }
            currentVertexOffset += UInt32(orderedPolygon.polygon.vertices.count)
        }

        return (drawing: DrawingPolygonBytes(vertices: unifiedVertices,
                                             indices: unifiedIndices),
                styles: styles,
                overviewStyleMasks: overviewStyleMasks)
    }

    private func makeDrawingGeometryLayer(
        drawing: DrawingPolygonBytes,
        styles: [TilePolygonStyle],
        overviewStyleMasks: [Float]
    ) -> DrawingGeometryLayer {
        DrawingGeometryLayer(drawing: drawing,
                             styles: styles,
                             overviewStyleMasks: overviewStyleMasks)
    }

    private func makeEmptyDrawingGeometryLayer() -> DrawingGeometryLayer {
        makeDrawingGeometryLayer(drawing: DrawingPolygonBytes(vertices: [], indices: []),
                                 styles: [],
                                 overviewStyleMasks: [])
    }
    
    func unificationStage(readingStageResult: ReadingStageResult) -> UnificationStageResult {
        let polygonByStyle = readingStageResult.polygonByStyle
        let roadPolygonByStyle = readingStageResult.roadPolygonByStyle
        let bridgePolygonByStyle = readingStageResult.bridgePolygonByStyle
        _ = readingStageResult.rawLineByStyle
        let extrudedByStyle = readingStageResult.extrudedByStyle

        let groundLayer = unifyPolygonLayer(polygonByStyle: polygonByStyle,
                                            stylesByKey: readingStageResult.styles)
        let emptyRoadLayer = makeEmptyDrawingGeometryLayer()
        let roadPhases: RoadStructureBuckets<RoadGeometryPhases<DrawingGeometryLayer>>
        if readingStageResult.orderedRoadPolygons.isEmpty {
            let unifiedRoadLayer = unifyPolygonLayer(polygonByStyle: roadPolygonByStyle,
                                                     stylesByKey: readingStageResult.roadStyles)
            roadPhases = RoadStructureBuckets(
                tunnel: RoadGeometryPhases(shadow: emptyRoadLayer,
                                           casing: emptyRoadLayer,
                                           fill: emptyRoadLayer,
                                           detail: emptyRoadLayer,
                                           overlay: emptyRoadLayer),
                ground: RoadGeometryPhases(shadow: emptyRoadLayer,
                                           casing: emptyRoadLayer,
                                           fill: makeDrawingGeometryLayer(drawing: unifiedRoadLayer.drawing,
                                                                         styles: unifiedRoadLayer.styles,
                                                                         overviewStyleMasks: unifiedRoadLayer.overviewStyleMasks),
                                           detail: emptyRoadLayer,
                                           overlay: emptyRoadLayer),
                bridge: RoadGeometryPhases(shadow: emptyRoadLayer,
                                           casing: emptyRoadLayer,
                                           fill: emptyRoadLayer,
                                           detail: emptyRoadLayer,
                                           overlay: emptyRoadLayer)
            )
        } else {
            let orderedRoadPolygons = readingStageResult.orderedRoadPolygons
            func makeStructurePhases(_ structureKind: RoadStructureKind) -> RoadGeometryPhases<DrawingGeometryLayer> {
                func makePhase(_ role: RoadPassRole) -> DrawingGeometryLayer {
                    let layer = unifyOrderedRoadLayer(
                        orderedRoadPolygons: orderedRoadPolygons.filter {
                            $0.structureKind == structureKind && $0.passRole == role
                        },
                        stylesByKey: readingStageResult.roadStyles
                    )
                    return makeDrawingGeometryLayer(drawing: layer.drawing,
                                                    styles: layer.styles,
                                                    overviewStyleMasks: layer.overviewStyleMasks)
                }

                return RoadGeometryPhases(shadow: makePhase(.shadow),
                                          casing: makePhase(.casing),
                                          fill: makePhase(.fill),
                                          detail: makePhase(.detail),
                                          overlay: makePhase(.overlay))
            }

            roadPhases = RoadStructureBuckets(
                tunnel: makeStructurePhases(.tunnel),
                ground: makeStructurePhases(.ground),
                bridge: makeStructurePhases(.bridge)
            )
        }
        let bridgeLayer = unifyPolygonLayer(polygonByStyle: bridgePolygonByStyle,
                                            stylesByKey: readingStageResult.bridgeStyles)
        var unifiedExtrudedVertices: [ExtrudedVertexIn] = []
        var unifiedExtrudedIndices: [UInt32] = []
        var currentExtrudedVertexOffset: UInt32 = 0
        var nextGlobalSurfaceID: UInt32 = 1
        let totalExtrudedVertexCount = extrudedByStyle.values.reduce(0) { partial, meshes in
            partial + meshes.reduce(0) { meshPartial, mesh in
                meshPartial + mesh.vertices.count
            }
        }
        let totalExtrudedIndexCount = extrudedByStyle.values.reduce(0) { partial, meshes in
            partial + meshes.reduce(0) { meshPartial, mesh in
                meshPartial + mesh.indices.count
            }
        }

        unifiedExtrudedVertices.reserveCapacity(totalExtrudedVertexCount)
        unifiedExtrudedIndices.reserveCapacity(totalExtrudedIndexCount)

        let styleKeys = extrudedByStyle.keys
            .filter { extrudedByStyle[$0]?.isEmpty == false }
            .sorted()
        var styleIndexByKey: [UInt8: UInt8] = [:]
        var extrudedStyles: [TilePolygonStyle] = []
        styleIndexByKey.reserveCapacity(styleKeys.count)
        extrudedStyles.reserveCapacity(styleKeys.count)
        for (index, styleKey) in styleKeys.enumerated() {
            if index > Int(UInt8.max) {
                assertionFailure("Too many styles for tile pipeline.")
                continue
            }
            styleIndexByKey[styleKey] = UInt8(index)
            if let style = readingStageResult.styles[styleKey] {
                extrudedStyles.append(TilePolygonStyle(color: style.color))
            }
        }

        for styleKey in styleKeys {
            let styleBufferIndex = styleIndexByKey[styleKey] ?? 0
            if let extrudedMeshes = extrudedByStyle[styleKey] {
                for extrudedMesh in extrudedMeshes {
                    var surfaceIDRemap: [UInt32: UInt32] = [:]
                    surfaceIDRemap.reserveCapacity(8)
                    for vertex in extrudedMesh.vertices {
                        let globalSurfaceID: UInt32
                        if let existingSurfaceID = surfaceIDRemap[vertex.surfaceID] {
                            globalSurfaceID = existingSurfaceID
                        } else {
                            globalSurfaceID = nextGlobalSurfaceID
                            nextGlobalSurfaceID &+= 1
                            surfaceIDRemap[vertex.surfaceID] = globalSurfaceID
                        }
                        unifiedExtrudedVertices.append(ExtrudedVertexIn(position: vertex.position,
                                                                        normal: vertex.normal,
                                                                        styleIndex: styleBufferIndex,
                                                                        surfaceID: globalSurfaceID))
                    }
                    for index in extrudedMesh.indices {
                        unifiedExtrudedIndices.append(index + currentExtrudedVertexOffset)
                    }
                    currentExtrudedVertexOffset += UInt32(extrudedMesh.vertices.count)
                }
            }
        }
        
        return UnificationStageResult(
            drawingPolygon: groundLayer.drawing,
            drawingRoadPhases: roadPhases,
            drawingBridgePolygon: bridgeLayer.drawing,
            drawingExtruded: DrawingExtrudedBytes(
                vertices: unifiedExtrudedVertices,
                indices: unifiedExtrudedIndices,
                styles: extrudedStyles
            ),
            styles: groundLayer.styles,
            overviewStyleMasks: groundLayer.overviewStyleMasks,
            bridgeStyles: bridgeLayer.styles,
            bridgeOverviewStyleMasks: bridgeLayer.overviewStyleMasks
        )
    }
}
