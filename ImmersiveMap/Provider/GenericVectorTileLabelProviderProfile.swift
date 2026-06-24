// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct GenericVectorTileLabelProviderProfile: VectorTileLabelProviderProfile {
    let providerID: String
    let languagePreferences: VectorTileLabelLanguagePreferences

    init(providerID: String,
         settings: ImmersiveMapSettings) {
        self.providerID = providerID
        self.languagePreferences = VectorTileLabelLanguagePreferences.from(
            settingsLanguage: settings.labels.language,
            fallbackPolicy: settings.labels.fallbackPolicy
        )
    }

    func sortKey(properties: [String: VectorTile_Tile.Value]) -> Int {
        let keys = ["rank", "sort_rank", "labelrank", "sizerank", "symbolrank"]
        for key in keys {
            guard let value = properties[key], let rank = parseIntValue(value) else {
                continue
            }
            return max(0, rank)
        }
        return 0
    }

    func collisionRank(layerName: String, sortKey: Int) -> Int {
        sortKey
    }

    func includesBasePointLabel(layerName: String,
                                properties: [String: VectorTile_Tile.Value],
                                tileZoom: Int,
                                sortKey: Int) -> Bool {
        properties["name"]?.stringValue.isEmpty == false
            || properties["name_en"]?.stringValue.isEmpty == false
            || properties["name:en"]?.stringValue.isEmpty == false
    }

    func identity(feature: VectorTileLabelFeature, text: String, kind: String) -> VectorTileLabelIdentity {
        if let featureID = feature.featureID {
            return .providerFeature(providerID: providerID,
                                    layerName: feature.layerName,
                                    featureID: featureID)
        }
        return .tileLocal(tile: feature.tile,
                          layerName: feature.layerName,
                          text: text,
                          anchor: feature.anchor)
    }

    func normalizedKind(layerName: String, properties: [String: VectorTile_Tile.Value]) -> String {
        [layerName, properties["class"]?.stringValue, properties["type"]?.stringValue]
            .compactMap { value in
                guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                      normalized.isEmpty == false else {
                    return nil
                }
                return normalized
            }
            .joined(separator: ":")
    }

    func isHouseNumberLayer(_ layerName: String) -> Bool {
        false
    }

    private func parseIntValue(_ value: VectorTile_Tile.Value) -> Int? {
        if value.hasIntValue {
            return Int(value.intValue)
        }
        if value.hasUintValue {
            return Int(value.uintValue)
        }
        if value.hasSintValue {
            return Int(value.sintValue)
        }
        if value.hasDoubleValue {
            return Int(value.doubleValue)
        }
        if value.hasFloatValue {
            return Int(value.floatValue)
        }
        if value.hasStringValue {
            return Int(value.stringValue)
        }
        return nil
    }
}
