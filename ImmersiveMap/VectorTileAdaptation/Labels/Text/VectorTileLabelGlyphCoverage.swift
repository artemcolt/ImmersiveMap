// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct VectorTileLabelGlyphCoverage {
    static let currentAtlas = VectorTileLabelGlyphCoverage.legacyCurrentAtlas
    static let allASCIIForTests = VectorTileLabelGlyphCoverage(supportedScalars: Set(UInt32(32)...UInt32(126)))

    private static let layoutControls: Set<UInt32> = [9, 10, 13, 32]
    private static let legacyCurrentAtlas = VectorTileLabelGlyphCoverage(
        supportedScalars: Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-=[]{}|;:'\\\",./<>?"
            .unicodeScalars
            .map(\.value))
            .union(Set(UInt32(0x0400)...UInt32(0x04FF)))
    )

    private let supportedScalars: Set<UInt32>

    init(supportedScalars: Set<UInt32>) {
        self.supportedScalars = supportedScalars
    }

    init(atlasData: AtlasData, thinAtlasData: AtlasData) {
        self.supportedScalars = Set((atlasData.glyphs + thinAtlasData.glyphs).map(\.unicode))
    }

    func canRender(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy {
            supportedScalars.contains($0.value) || Self.layoutControls.contains($0.value)
        }
    }
}
