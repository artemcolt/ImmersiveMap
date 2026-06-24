// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import simd

final class GenericVectorTileStyle: ImmersiveMapStyle {
    private let providerID: String
    private let style: any ImmersiveMapVectorTileStyle
    private let mapBaseColors: ImmersiveMapBaseColors
    private let fallbackStyle: FeatureStyle

    init(providerID: String,
         style: any ImmersiveMapVectorTileStyle,
         settings: ImmersiveMapSettings.StyleSettings) {
        self.providerID = providerID
        self.style = style
        let baseColors = style.baseColors ?? settings.baseColors
        self.mapBaseColors = ImmersiveMapBaseColors(settings: baseColors)
        self.fallbackStyle = FeatureStyle(
            key: 0,
            color: settings.fallbackFeatureColor,
            parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 100)
        )
    }

    var preparedTileStyleRevision: UInt32 {
        style.cacheFingerprint
    }

    func getMapBaseColors() -> ImmersiveMapBaseColors {
        mapBaseColors
    }

    func makeStyle(data: DetFeatureStyleData) -> FeatureStyle {
        let context = ImmersiveMapFeatureStyleContext(
            providerID: providerID,
            layerName: data.layerName,
            tileZoom: data.tile.z,
            tileX: data.tile.x,
            tileY: data.tile.y,
            properties: ImmersiveMapFeatureProperties(values: data.properties)
        )
        let publicStyle = style.makeStyle(for: context)
        let key = styleKey(layerName: data.layerName, style: publicStyle)

        switch publicStyle {
        case .hidden:
            return FeatureStyle(
                key: key,
                color: SIMD4<Float>(0, 0, 0, 0),
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 0)
            )
        case .polygon(let color):
            return FeatureStyle(
                key: key,
                color: color,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 100)
            )
        case .line(let color, let width):
            return FeatureStyle(
                key: key,
                color: color,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: Double(max(Float(0), width)))
            )
        case .extrudedPolygon(let color, let heightScale, let anchorZoom, let fallbackHeight):
            return FeatureStyle(
                key: key,
                color: color,
                parseGeometryStyleData: TileMvtParser.ParseGeometryStyleData(lineWidth: 100),
                usesExtrusion: true,
                extrusionHeightScale: heightScale,
                extrusionAnchorZoom: anchorZoom,
                extrusionFallbackHeight: fallbackHeight
            )
        }
    }

    private func styleKey(layerName: String, style: ImmersiveMapFeatureStyle) -> UInt8 {
        var hash: UInt64 = 1469598103934665603
        mix(providerID, into: &hash)
        mix(layerName, into: &hash)
        mix(String(describing: style), into: &hash)
        return UInt8(3 + (hash % 205))
    }

    private func mix(_ string: String, into hash: inout UInt64) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
    }
}
