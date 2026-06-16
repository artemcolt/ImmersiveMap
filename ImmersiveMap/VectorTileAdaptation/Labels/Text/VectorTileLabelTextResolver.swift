// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct VectorTileLabelTextResolver {
    private let glyphCoverage: VectorTileLabelGlyphCoverage

    init(glyphCoverage: VectorTileLabelGlyphCoverage) {
        self.glyphCoverage = glyphCoverage
    }

    func resolveText(properties: [String: VectorTile_Tile.Value],
                     preferences: VectorTileLabelLanguagePreferences) -> String? {
        for candidate in preferences.fallbackChain {
            guard let text = properties[candidate.fieldName]?.stringValue,
                  text.isEmpty == false,
                  glyphCoverage.canRender(text) else {
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
}
