// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct VectorTileLabelGlyphCoverage {
    static let currentAtlas = VectorTileLabelGlyphCoverage()

    private static let latinSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let cyrillicSet = CharacterSet(charactersIn: UnicodeScalar(0x0400)!...UnicodeScalar(0x04FF)!)
    private static let digitsSet = CharacterSet(charactersIn: "0123456789")
    private static let punctuationSet = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:'\\\",./<>?")
    private static let whitespaceAndNewlinesSet = CharacterSet.whitespacesAndNewlines

    func canRender(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if VectorTileLabelGlyphCoverage.latinSet.contains(scalar) ||
                VectorTileLabelGlyphCoverage.cyrillicSet.contains(scalar) ||
                VectorTileLabelGlyphCoverage.digitsSet.contains(scalar) ||
                VectorTileLabelGlyphCoverage.punctuationSet.contains(scalar) ||
                VectorTileLabelGlyphCoverage.whitespaceAndNewlinesSet.contains(scalar) {
                continue
            }
            return false
        }
        return true
    }
}
