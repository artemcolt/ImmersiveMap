// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct VectorTileLabelTextResolver {
    private let glyphCoverage: VectorTileLabelGlyphCoverage

    private static let latinSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let cyrillicSet = CharacterSet(charactersIn: UnicodeScalar(0x0400)!...UnicodeScalar(0x04FF)!)

    init(glyphCoverage: VectorTileLabelGlyphCoverage) {
        self.glyphCoverage = glyphCoverage
    }

    func resolveText(properties: [String: VectorTile_Tile.Value],
                     preferences: VectorTileLabelLanguagePreferences) -> String? {
        for languageCode in preferences.fallbackChain {
            guard let text = text(for: languageCode, properties: properties),
                  text.isEmpty == false,
                  glyphCoverage.canRender(text) else {
                continue
            }

            if languageCode == .native,
               nativeTextMatchesSelectedLanguage(text, preferences: preferences) == false {
                continue
            }

            return text
        }

        return nil
    }

    func resolveHouseNumber(properties: [String: VectorTile_Tile.Value]) -> String? {
        guard let text = properties["house_num"]?.stringValue,
              text.isEmpty == false,
              glyphCoverage.canRender(text) else {
            return nil
        }
        return text
    }

    private func text(for languageCode: VectorTileLabelLanguagePreferences.LanguageCode,
                      properties: [String: VectorTile_Tile.Value]) -> String? {
        switch languageCode {
        case .russian:
            return properties["name_ru"]?.stringValue
        case .english:
            return properties["name_en"]?.stringValue
        case .native:
            return properties["name"]?.stringValue
        }
    }

    private func nativeTextMatchesSelectedLanguage(_ text: String,
                                                   preferences: VectorTileLabelLanguagePreferences) -> Bool {
        switch preferences.selectedLanguage {
        case .russian:
            return containsAny(from: VectorTileLabelTextResolver.cyrillicSet, in: text)
        case .english:
            return containsAny(from: VectorTileLabelTextResolver.latinSet, in: text) &&
                containsAny(from: VectorTileLabelTextResolver.cyrillicSet, in: text) == false
        case .native:
            return true
        }
    }

    private func containsAny(from set: CharacterSet, in text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if set.contains(scalar) {
                return true
            }
        }
        return false
    }
}
