# Vector Tile Adaptation Label Decisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an internal `VectorTileAdaptation/Labels` decision layer for provider-neutral point/base label decisions while preserving the existing renderer pipeline.

**Architecture:** Introduce small internal value types for label feature input, identity, priority, placement, and decisions. Add a Mapbox-oriented provider profile and decision engine that reproduces current point-label behavior, then adapt decisions back into `TileMvtParser.TextLabel` so runtime label caches and render code remain unchanged.

**Tech Stack:** Swift 5 package target, XCTest, existing MVT protobuf types, existing `Tile`, `LabelTextStyle`, `PoiSpriteIcon`, and `VectorTile_Tile.Value` models.

---

## File Structure

- Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelStableHasher.swift` for deterministic internal label keys.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelIdentity.swift` for explicit provider-feature, semantic, and tile-local identity.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelPriority.swift` for separated visibility, collision, deduplication, and draw ranks.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelPlacementIntent.swift` for collision padding and centered placement intent.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelFeature.swift` for decoded point feature context.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelDecision.swift` for the decision output.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelLanguagePreferences.swift` for internal language fallback chains.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelGlyphCoverage.swift` for renderability checks using current atlas coverage.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelTextResolver.swift` for provider-neutral text selection.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Providers/VectorTileLabelProviderProfile.swift` for provider schema decisions.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Providers/MapboxVectorTileLabelProviderProfile.swift` to reproduce current Mapbox-oriented behavior.
- Create `ImmersiveMap/VectorTileAdaptation/Labels/Decisions/VectorTileLabelDecisionEngine.swift` for the orchestration.
- Modify `ImmersiveMap/Tile/Parse/TileMvtParser.swift` to call the decision engine for point labels.
- Modify or remove `ImmersiveMap/Tile/Parse/TileLabelTextResolver.swift` after migration if no production code uses it.
- Add `Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift` for non-Metal unit coverage.

---

### Task 1: Core Identity And Priority Types

**Files:**
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelStableHasher.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelIdentity.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelPriority.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelPlacementIntent.swift`
- Test: `Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift`

- [ ] **Step 1: Write failing identity tests**

Add this file:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class VectorTileLabelDecisionEngineTests: XCTestCase {
    func testProviderFeatureIdentityParticipatesInCrossTileDeduplication() {
        let identity = VectorTileLabelIdentity.providerFeature(providerID: "mapbox",
                                                               layerName: "place_label",
                                                               featureID: 42)

        XCTAssertTrue(identity.participatesInCrossTileDeduplication)
        XCTAssertEqual(identity.runtimeKey,
                       VectorTileLabelIdentity.providerFeature(providerID: "mapbox",
                                                               layerName: "place_label",
                                                               featureID: 42).runtimeKey)
    }

    func testTileLocalIdentityIncludesTileCoordinates() {
        let first = VectorTileLabelIdentity.tileLocal(tile: Tile(x: 10, y: 20, z: 5),
                                                      layerName: "poi_label",
                                                      text: "Museum",
                                                      anchor: SIMD2<Int16>(100, 200))
        let second = VectorTileLabelIdentity.tileLocal(tile: Tile(x: 11, y: 20, z: 5),
                                                       layerName: "poi_label",
                                                       text: "Museum",
                                                       anchor: SIMD2<Int16>(100, 200))

        XCTAssertFalse(first.participatesInCrossTileDeduplication)
        XCTAssertNotEqual(first.runtimeKey, second.runtimeKey)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: compile failure because `VectorTileLabelIdentity` is not defined.

- [ ] **Step 3: Add deterministic hasher**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelStableHasher.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct VectorTileLabelStableHasher {
    private static let seed: UInt64 = 1469598103934665603
    private static let prime: UInt64 = 1099511628211

    private var hash: UInt64 = seed

    mutating func combine(_ value: UInt64) {
        hash ^= value
        hash &*= Self.prime
    }

    mutating func combine(_ value: Int) {
        combine(UInt64(bitPattern: Int64(value)))
    }

    mutating func combine(_ value: UInt32) {
        combine(UInt64(value))
    }

    mutating func combine(_ value: Int16) {
        combine(UInt64(UInt16(bitPattern: value)))
    }

    mutating func combine(_ value: String) {
        combine(UInt64(value.utf8.count))
        for byte in value.utf8 {
            combine(UInt64(byte))
        }
    }

    func finalize() -> UInt64 {
        hash
    }
}
```

- [ ] **Step 4: Add identity, priority, and placement types**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelIdentity.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import simd

enum VectorTileLabelIdentity: Equatable {
    case providerFeature(providerID: String, layerName: String, featureID: UInt64)
    case semantic(providerID: String, kind: String, text: String, worldBucket: SIMD2<Int32>)
    case tileLocal(tile: Tile, layerName: String, text: String, anchor: SIMD2<Int16>)

    var participatesInCrossTileDeduplication: Bool {
        switch self {
        case .providerFeature, .semantic:
            return true
        case .tileLocal:
            return false
        }
    }

    var runtimeKey: UInt64 {
        var hasher = VectorTileLabelStableHasher()
        switch self {
        case let .providerFeature(providerID, layerName, featureID):
            hasher.combine("providerFeature")
            hasher.combine(providerID)
            hasher.combine(layerName)
            hasher.combine(featureID)
        case let .semantic(providerID, kind, text, worldBucket):
            hasher.combine("semantic")
            hasher.combine(providerID)
            hasher.combine(kind)
            hasher.combine(text)
            hasher.combine(Int(worldBucket.x))
            hasher.combine(Int(worldBucket.y))
        case let .tileLocal(tile, layerName, text, anchor):
            hasher.combine("tileLocal")
            hasher.combine(tile.x)
            hasher.combine(tile.y)
            hasher.combine(tile.z)
            hasher.combine(layerName)
            hasher.combine(text)
            hasher.combine(anchor.x)
            hasher.combine(anchor.y)
        }
        return hasher.finalize()
    }
}
```

Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelPriority.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct VectorTileLabelPriority: Equatable {
    let visibilityRank: Int
    let collisionRank: Int
    let deduplicationRank: Int
    let drawRank: Int

    init(visibilityRank: Int,
         collisionRank: Int,
         deduplicationRank: Int,
         drawRank: Int) {
        self.visibilityRank = visibilityRank
        self.collisionRank = collisionRank
        self.deduplicationRank = deduplicationRank
        self.drawRank = drawRank
    }
}
```

Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelPlacementIntent.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import simd

enum VectorTileLabelCollisionShape: Equatable {
    case rect
}

enum VectorTileLabelAnchorMode: Equatable {
    case centered
}

struct VectorTileLabelPlacementIntent: Equatable {
    let collisionPaddingPx: Float
    let collisionShape: VectorTileLabelCollisionShape
    let anchorMode: VectorTileLabelAnchorMode
    let screenOffsetPx: SIMD2<Float>

    static let centered = VectorTileLabelPlacementIntent(collisionPaddingPx: 0,
                                                         collisionShape: .rect,
                                                         anchorMode: .centered,
                                                         screenOffsetPx: .zero)
}
```

- [ ] **Step 5: Run tests and verify they pass**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add ImmersiveMap/VectorTileAdaptation/Labels/Core Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift
git commit -m "feat: add vector tile label identity model"
```

---

### Task 2: Text Resolution And Glyph Coverage

**Files:**
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelLanguagePreferences.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelGlyphCoverage.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelTextResolver.swift`
- Modify: `Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift`

- [ ] **Step 1: Add failing text resolver tests**

Append these methods to `VectorTileLabelDecisionEngineTests`:

```swift
    func testRussianPreferencesPreferRussianThenNativeThenEnglish() {
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Москва"),
            "name_en": stringValue("Moscow"),
            "name_ru": stringValue("Москва")
        ]

        let text = resolver.resolveText(properties: properties,
                                        preferences: .from(settingsLanguage: .russian))

        XCTAssertEqual(text, "Москва")
    }

    func testEnglishPreferencesPreferEnglishThenNativeThenRussian() {
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("Москва"),
            "name_en": stringValue("Moscow"),
            "name_ru": stringValue("Москва")
        ]

        let text = resolver.resolveText(properties: properties,
                                        preferences: .from(settingsLanguage: .english))

        XCTAssertEqual(text, "Moscow")
    }

    func testUnsupportedGlyphCoverageRejectsText() {
        let resolver = VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        let properties: [String: VectorTile_Tile.Value] = [
            "name": stringValue("東京")
        ]

        let text = resolver.resolveText(properties: properties,
                                        preferences: .from(settingsLanguage: .english))

        XCTAssertNil(text)
    }

    private func stringValue(_ value: String) -> VectorTile_Tile.Value {
        var tileValue = VectorTile_Tile.Value()
        tileValue.stringValue = value
        return tileValue
    }
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: compile failure because text resolver types are not defined.

- [ ] **Step 3: Add language preferences**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelLanguagePreferences.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct VectorTileLabelLanguagePreferences: Equatable {
    enum LanguageCode: Equatable {
        case russian
        case english
        case native
    }

    let fallbackChain: [LanguageCode]

    static func from(settingsLanguage: ImmersiveMapSettings.LabelLanguage) -> VectorTileLabelLanguagePreferences {
        switch settingsLanguage {
        case .russian:
            return VectorTileLabelLanguagePreferences(fallbackChain: [.russian, .native, .english])
        case .english:
            return VectorTileLabelLanguagePreferences(fallbackChain: [.english, .native, .russian])
        }
    }
}
```

- [ ] **Step 4: Add glyph coverage**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelGlyphCoverage.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct VectorTileLabelGlyphCoverage {
    static let currentAtlas = VectorTileLabelGlyphCoverage()

    private static let latinSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let cyrillicSet = CharacterSet(charactersIn: UnicodeScalar(0x0400)!...UnicodeScalar(0x04FF)!)
    private static let digitsSet = CharacterSet(charactersIn: "0123456789")
    private static let punctuationSet = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:'\\\",./<>?")

    func canRender(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if Self.latinSet.contains(scalar) ||
                Self.cyrillicSet.contains(scalar) ||
                Self.digitsSet.contains(scalar) ||
                Self.punctuationSet.contains(scalar) ||
                CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            return false
        }
        return true
    }
}
```

- [ ] **Step 5: Add text resolver**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Text/VectorTileLabelTextResolver.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct VectorTileLabelTextResolver {
    private let glyphCoverage: VectorTileLabelGlyphCoverage

    init(glyphCoverage: VectorTileLabelGlyphCoverage) {
        self.glyphCoverage = glyphCoverage
    }

    func resolveText(properties: [String: VectorTile_Tile.Value],
                     preferences: VectorTileLabelLanguagePreferences) -> String? {
        for language in preferences.fallbackChain {
            guard let text = text(for: language, properties: properties),
                  text.isEmpty == false,
                  glyphCoverage.canRender(text) else {
                continue
            }
            if language == .native,
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

    private func text(for language: VectorTileLabelLanguagePreferences.LanguageCode,
                      properties: [String: VectorTile_Tile.Value]) -> String? {
        switch language {
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
        guard let selected = preferences.fallbackChain.first else {
            return true
        }
        let hasCyrillic = containsCyrillic(text)
        let hasLatin = containsLatin(text)
        switch selected {
        case .russian:
            return hasCyrillic
        case .english:
            return hasLatin && hasCyrillic == false
        case .native:
            return true
        }
    }

    private func containsLatin(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").contains($0) }
    }

    private func containsCyrillic(_ text: String) -> Bool {
        let cyrillic = CharacterSet(charactersIn: UnicodeScalar(0x0400)!...UnicodeScalar(0x04FF)!)
        return text.unicodeScalars.contains { cyrillic.contains($0) }
    }
}
```

- [ ] **Step 6: Run tests and verify they pass**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add ImmersiveMap/VectorTileAdaptation/Labels/Text Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift
git commit -m "feat: add vector tile label text resolver"
```

---

### Task 3: Mapbox Provider Profile

**Files:**
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelFeature.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelDecision.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Providers/VectorTileLabelProviderProfile.swift`
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Providers/MapboxVectorTileLabelProviderProfile.swift`
- Modify: `Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift`

- [ ] **Step 1: Add failing provider profile tests**

Append these methods to `VectorTileLabelDecisionEngineTests`:

```swift
    func testMapboxProfileExcludesRoadAndTransitPointLabelLayers() {
        let profile = MapboxVectorTileLabelProviderProfile(settings: .default)

        XCTAssertFalse(profile.includesBasePointLabel(layerName: "road_label",
                                                      properties: [:],
                                                      tileZoom: 15,
                                                      sortKey: 0))
        XCTAssertFalse(profile.includesBasePointLabel(layerName: "transit_stop_label",
                                                      properties: [:],
                                                      tileZoom: 15,
                                                      sortKey: 0))
    }

    func testMapboxProfileAllowsHouseNumberAtConfiguredZoom() {
        let profile = MapboxVectorTileLabelProviderProfile(settings: .default)

        XCTAssertFalse(profile.includesBasePointLabel(layerName: "housenum_label",
                                                      properties: [:],
                                                      tileZoom: 14,
                                                      sortKey: 0))
        XCTAssertTrue(profile.includesBasePointLabel(layerName: "housenum_label",
                                                     properties: [:],
                                                     tileZoom: 15,
                                                     sortKey: 0))
    }

    func testMapboxProfilePushesPoiCollisionBehindSettlementCollision() {
        let profile = MapboxVectorTileLabelProviderProfile(settings: .default)

        XCTAssertLessThan(profile.collisionRank(layerName: "place_label", sortKey: 50),
                          profile.collisionRank(layerName: "poi_label", sortKey: 50))
    }
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: compile failure because provider profile types are not defined.

- [ ] **Step 3: Add feature and decision models**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelFeature.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import simd

struct VectorTileLabelFeature {
    let providerID: String
    let tile: Tile
    let layerName: String
    let featureID: UInt64?
    let anchor: SIMD2<Int16>
    let properties: [String: VectorTile_Tile.Value]
}
```

Create `ImmersiveMap/VectorTileAdaptation/Labels/Core/VectorTileLabelDecision.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct VectorTileLabelDecision {
    let text: String
    let identity: VectorTileLabelIdentity
    let priority: VectorTileLabelPriority
    let placement: VectorTileLabelPlacementIntent
    let style: LabelTextStyle
    let poiIcon: PoiSpriteIcon?
}
```

- [ ] **Step 4: Add provider protocol**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Providers/VectorTileLabelProviderProfile.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

protocol VectorTileLabelProviderProfile {
    var providerID: String { get }
    var languagePreferences: VectorTileLabelLanguagePreferences { get }

    func sortKey(properties: [String: VectorTile_Tile.Value]) -> Int
    func collisionRank(layerName: String, sortKey: Int) -> Int
    func includesBasePointLabel(layerName: String,
                                properties: [String: VectorTile_Tile.Value],
                                tileZoom: Int,
                                sortKey: Int) -> Bool
    func identity(feature: VectorTileLabelFeature,
                  text: String,
                  kind: String) -> VectorTileLabelIdentity
    func normalizedKind(layerName: String,
                        properties: [String: VectorTile_Tile.Value]) -> String
    func isHouseNumberLayer(_ layerName: String) -> Bool
}
```

- [ ] **Step 5: Add Mapbox profile with current behavior**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Providers/MapboxVectorTileLabelProviderProfile.swift` by moving the current point-label policy from `TileMvtParser`. The file should define:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import simd

struct MapboxVectorTileLabelProviderProfile: VectorTileLabelProviderProfile {
    private static let houseNumberCollisionPriorityOffset: Int = 100_000
    private static let poiCollisionPriorityOffset: Int = 200_000

    let providerID = "mapbox"
    private let settings: ImmersiveMapSettings

    init(settings: ImmersiveMapSettings) {
        self.settings = settings
    }

    var languagePreferences: VectorTileLabelLanguagePreferences {
        .from(settingsLanguage: settings.labels.language)
    }

    func sortKey(properties: [String: VectorTile_Tile.Value]) -> Int {
        let classValue = properties["class"]?.stringValue
        let typeValue = properties["type"]?.stringValue
        let rankReferenceValue = typeValue ?? classValue
        let rankKeys = ["symbolrank", "sizerank", "filterrank", "rank", "scalerank", "place_rank", "localrank", "labelrank"]
        var baseRank: Int?
        for key in rankKeys {
            if let value = properties[key], let rank = parseIntValue(value) {
                baseRank = rank
                break
            }
        }
        let rankValue = baseRank ?? labelClassRank(rankReferenceValue)
        let popBoost = populationBoost(properties: properties)
        let capitalBoost = isTruthy(properties["capital"]) ? 30 : 0
        return max(0, rankValue * 10 + labelClassBias(rankReferenceValue) - popBoost - capitalBoost)
    }

    func collisionRank(layerName: String, sortKey: Int) -> Int {
        let normalizedLayerName = layerName.lowercased()
        if isHouseNumberLayer(normalizedLayerName) {
            return Self.houseNumberCollisionPriorityOffset + sortKey
        }
        if normalizedLayerName == "poi_label" {
            return Self.poiCollisionPriorityOffset + sortKey
        }
        return sortKey
    }

    func includesBasePointLabel(layerName: String,
                                properties: [String: VectorTile_Tile.Value],
                                tileZoom: Int,
                                sortKey: Int) -> Bool {
        let normalizedLayerName = layerName.lowercased()
        let classValue = properties["class"]?.stringValue
        let typeValue = properties["type"]?.stringValue

        if normalizedLayerName == "road_label" || normalizedLayerName.contains("transit") {
            return false
        }
        if isHouseNumberLayer(normalizedLayerName) {
            return settings.labels.houseNumbers.enabled && tileZoom >= settings.labels.houseNumbers.minimumZoom
        }
        if normalizedLayerName == "poi_label" {
            if isLandmark(classValue: classValue, typeValue: typeValue) {
                return tileZoom >= settings.labels.landmarks.minimumZoom && sortKey <= landmarkSortKeyThreshold(for: tileZoom)
            }
            return tileZoom >= 13 && sortKey <= poiSortKeyThreshold(for: tileZoom)
        }
        if normalizedLayerName == "airport_label" {
            return tileZoom >= 8 && sortKey <= airportSortKeyThreshold(for: tileZoom)
        }
        if isCapital(properties: properties) {
            return tileZoom >= 2 && tileZoom <= settings.labels.settlementVisibility.capitalMaximumZoom
        }
        if isCity(classValue: classValue, typeValue: typeValue) {
            return tileZoom >= 2 &&
                tileZoom <= settings.labels.settlementVisibility.cityMaximumZoom &&
                sortKey <= citySortKeyThreshold(for: tileZoom)
        }
        if isDistrict(classValue: classValue, typeValue: typeValue) {
            return tileZoom >= 9 && sortKey <= districtSortKeyThreshold(for: tileZoom)
        }
        if isSmallSettlement(typeValue: typeValue) {
            return tileZoom >= 10 &&
                tileZoom <= settings.labels.settlementVisibility.smallSettlementMaximumZoom &&
                sortKey <= smallSettlementSortKeyThreshold(for: tileZoom)
        }
        return true
    }

    func identity(feature: VectorTileLabelFeature,
                  text: String,
                  kind: String) -> VectorTileLabelIdentity {
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

    func normalizedKind(layerName: String,
                        properties: [String: VectorTile_Tile.Value]) -> String {
        let classValue = properties["class"]?.stringValue ?? ""
        let typeValue = properties["type"]?.stringValue ?? ""
        return [layerName.lowercased(), classValue.lowercased(), typeValue.lowercased()]
            .filter { $0.isEmpty == false }
            .joined(separator: ":")
    }

    func isHouseNumberLayer(_ layerName: String) -> Bool {
        layerName.lowercased() == "housenum_label"
    }
}
```

Add private helpers in the same file by moving the corresponding logic from `TileMvtParser`: `parseIntValue`, `parseDoubleValue`, `isTruthy`, `populationBoost`, `labelClassRank`, `labelClassBias`, `isCapital`, `isLandmark`, `isCity`, `isDistrict`, `isSmallSettlement`, and threshold functions. Keep their returned values identical to the current `TileMvtParser` functions.

- [ ] **Step 6: Run tests and verify they pass**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add ImmersiveMap/VectorTileAdaptation/Labels/Core ImmersiveMap/VectorTileAdaptation/Labels/Providers Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift
git commit -m "feat: add mapbox vector tile label profile"
```

---

### Task 4: Decision Engine And Existing TextLabel Adapter

**Files:**
- Create: `ImmersiveMap/VectorTileAdaptation/Labels/Decisions/VectorTileLabelDecisionEngine.swift`
- Modify: `Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift`

- [ ] **Step 1: Add failing decision engine tests**

Append this method to `VectorTileLabelDecisionEngineTests`:

```swift
    func testDecisionEngineBuildsTextLabelCompatibleDecision() {
        let style = LabelTextStyle(key: 30,
                                   fillColor: SIMD3<Float>(0.1, 0.2, 0.3),
                                   strokeColor: SIMD3<Float>(1, 1, 1),
                                   strokeWidthPx: 2,
                                   sizePx: 24,
                                   weight: .thin)
        let engine = VectorTileLabelDecisionEngine(profile: MapboxVectorTileLabelProviderProfile(settings: .default),
                                                   textResolver: VectorTileLabelTextResolver(glyphCoverage: .currentAtlas))
        let feature = VectorTileLabelFeature(providerID: "mapbox",
                                             tile: Tile(x: 123, y: 456, z: 10),
                                             layerName: "place_label",
                                             featureID: 7,
                                             anchor: SIMD2<Int16>(2048, 2048),
                                             properties: [
                                                "name_en": stringValue("Moscow"),
                                                "type": stringValue("city")
                                             ])

        let decision = engine.makePointLabelDecision(feature: feature,
                                                     style: style,
                                                     poiIcon: nil)

        XCTAssertEqual(decision?.text, "Moscow")
        XCTAssertEqual(decision?.priority.collisionRank,
                       MapboxVectorTileLabelProviderProfile(settings: .default).collisionRank(layerName: "place_label",
                                                                                              sortKey: decision?.priority.visibilityRank ?? -1))
        XCTAssertEqual(decision?.identity,
                       .providerFeature(providerID: "mapbox", layerName: "place_label", featureID: 7))
    }
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: compile failure because `VectorTileLabelDecisionEngine` is not defined.

- [ ] **Step 3: Add decision engine**

Create `ImmersiveMap/VectorTileAdaptation/Labels/Decisions/VectorTileLabelDecisionEngine.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct VectorTileLabelDecisionEngine {
    private let profile: VectorTileLabelProviderProfile
    private let textResolver: VectorTileLabelTextResolver

    init(profile: VectorTileLabelProviderProfile,
         textResolver: VectorTileLabelTextResolver) {
        self.profile = profile
        self.textResolver = textResolver
    }

    func makePointLabelDecision(feature: VectorTileLabelFeature,
                                style: LabelTextStyle,
                                poiIcon: PoiSpriteIcon?) -> VectorTileLabelDecision? {
        let text: String?
        if profile.isHouseNumberLayer(feature.layerName) {
            text = textResolver.resolveHouseNumber(properties: feature.properties)
        } else {
            text = textResolver.resolveText(properties: feature.properties,
                                            preferences: profile.languagePreferences)
        }

        guard let resolvedText = text else {
            return nil
        }

        let sortKey = profile.sortKey(properties: feature.properties)
        guard profile.includesBasePointLabel(layerName: feature.layerName,
                                             properties: feature.properties,
                                             tileZoom: feature.tile.z,
                                             sortKey: sortKey) else {
            return nil
        }

        let collisionRank = profile.collisionRank(layerName: feature.layerName,
                                                  sortKey: sortKey)
        let kind = profile.normalizedKind(layerName: feature.layerName,
                                          properties: feature.properties)
        let identity = profile.identity(feature: feature,
                                        text: resolvedText,
                                        kind: kind)
        return VectorTileLabelDecision(text: resolvedText,
                                       identity: identity,
                                       priority: VectorTileLabelPriority(visibilityRank: sortKey,
                                                                         collisionRank: collisionRank,
                                                                         deduplicationRank: sortKey,
                                                                         drawRank: sortKey),
                                       placement: .centered,
                                       style: style,
                                       poiIcon: poiIcon)
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add ImmersiveMap/VectorTileAdaptation/Labels/Decisions Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift
git commit -m "feat: add vector tile label decision engine"
```

---

### Task 5: Integrate Point Labels In TileMvtParser

**Files:**
- Modify: `ImmersiveMap/Tile/Parse/TileMvtParser.swift`
- Modify: `ImmersiveMap/Tile/Parse/Types/TileMvtParser+TextLabel.swift`
- Modify: `Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift`

- [ ] **Step 1: Add adapter test for existing TextLabel runtime key**

Append this method to `VectorTileLabelDecisionEngineTests`:

```swift
    func testDecisionRuntimeKeyCanBackExistingTextLabelKey() {
        let identity = VectorTileLabelIdentity.tileLocal(tile: Tile(x: 1, y: 2, z: 3),
                                                         layerName: "poi_label",
                                                         text: "Cafe",
                                                         anchor: SIMD2<Int16>(120, 240))

        XCTAssertEqual(identity.runtimeKey,
                       VectorTileLabelIdentity.tileLocal(tile: Tile(x: 1, y: 2, z: 3),
                                                         layerName: "poi_label",
                                                         text: "Cafe",
                                                         anchor: SIMD2<Int16>(120, 240)).runtimeKey)
    }
```

- [ ] **Step 2: Run tests**

Run:

```bash
swift test --filter VectorTileLabelDecisionEngineTests
```

Expected: tests pass before parser integration.

- [ ] **Step 3: Extend TextLabel initializer for decision keys**

Modify `ImmersiveMap/Tile/Parse/Types/TileMvtParser+TextLabel.swift` so `TextLabel` has an additional initializer:

```swift
        init(text: String,
             position: SIMD2<Int16>,
             key: UInt64,
             sortKey: Int,
             collisionPriority: Int,
             textStyle: LabelTextStyle,
             poiIcon: PoiSpriteIcon? = nil) {
            self.text = text
            self.position = position
            self.key = key
            self.sortKey = sortKey
            self.collisionPriority = collisionPriority
            self.textStyle = textStyle
            self.poiIcon = poiIcon
        }
```

Keep the existing initializer so road and fallback call sites continue compiling until they are migrated or intentionally left alone.

- [ ] **Step 4: Add decision engine property to TileMvtParser**

Modify `ImmersiveMap/Tile/Parse/TileMvtParser.swift` near the stored properties:

```swift
    private let labelDecisionEngine: VectorTileLabelDecisionEngine
```

Modify the initializer:

```swift
    init(determineFeatureStyle: DetermineFeatureStyle, config: ImmersiveMapSettings) {
        self.determineFeatureStyle = determineFeatureStyle
        self.config = config
        self.labelTextResolver = TileLabelTextResolver(config: config)
        self.labelDecisionEngine = VectorTileLabelDecisionEngine(
            profile: MapboxVectorTileLabelProviderProfile(settings: config),
            textResolver: VectorTileLabelTextResolver(glyphCoverage: .currentAtlas)
        )
    }
```

Keep `labelTextResolver` temporarily because road labels still use `resolveLabelText` in the current code.

- [ ] **Step 5: Replace point label decision block**

In the `feature.type == .point` branch of `TileMvtParser.readingStage`, replace the current block that resolves text, sort key, collision priority, and `shouldIncludePointLabel` with:

```swift
                    guard let labelTextStyle = style.labelTextStyle else { continue }
                    let points = decodePoint.decode(geometry: feature.geometry)
                    let featureId = feature.hasID ? feature.id : nil
                    let poiIcon = poiSpriteResolver.resolve(attributes: attributes, layerName: layerName)

                    for point in points where isPointInsideTile(point) {
                        let anchor = SIMD2<Int16>(Int16(point.x), Int16(point.y))
                        let labelFeature = VectorTileLabelFeature(providerID: "mapbox",
                                                                  tile: tile,
                                                                  layerName: layerName,
                                                                  featureID: featureId,
                                                                  anchor: anchor,
                                                                  properties: attributes)
                        guard let decision = labelDecisionEngine.makePointLabelDecision(feature: labelFeature,
                                                                                        style: labelTextStyle,
                                                                                        poiIcon: poiIcon) else {
                            continue
                        }
                        textLabels.append(TextLabel(text: decision.text,
                                                    position: anchor,
                                                    key: decision.identity.runtimeKey,
                                                    sortKey: decision.priority.visibilityRank,
                                                    collisionPriority: decision.priority.collisionRank,
                                                    textStyle: decision.style,
                                                    poiIcon: decision.poiIcon))
                    }
```

- [ ] **Step 6: Build tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add ImmersiveMap/Tile/Parse/TileMvtParser.swift ImmersiveMap/Tile/Parse/Types/TileMvtParser+TextLabel.swift Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift
git commit -m "feat: route point labels through vector tile adaptation"
```

---

### Task 6: Cleanup And Regression Check

**Files:**
- Modify: `ImmersiveMap/Tile/Parse/TileMvtParser.swift`
- Modify: `ImmersiveMap/Tile/Parse/TileLabelTextResolver.swift` if it is still needed only for road labels.
- Modify: `Docs/superpowers/specs/2026-06-05-vector-tile-adaptation-label-decisions-design.md` only if implementation intentionally differs from the approved design.

- [ ] **Step 1: Search for migrated point-label helper usage**

Run:

```bash
rg -n "pointLabelText|pointLabelCollisionPriority|shouldIncludePointLabel|labelSortKey\\(" ImmersiveMap/Tile/Parse
```

Expected: only unused helper definitions remain in `TileMvtParser.swift`, or no matches.

- [ ] **Step 2: Remove unused point-label helpers**

If the search shows these helpers are unused after point-label integration, remove their definitions from `TileMvtParser.swift`:

```text
labelSortKey
pointLabelText
pointLabelCollisionPriority
shouldIncludePointLabel
hasCapitalPriority
isRoadPointLabelLayer
isHouseNumberPointLabelLayer
isTransitPointLabelLayer
isAirportPointLabelLayer
isLandmarkPointLabel
normalizeLandmarkValue
isContinentPointLabel
isOceanPointLabel
isDistrictPointLabel
isCityPointLabel
isNaturalPointLabel
isSmallSettlementPointLabel
landmarkSortKeyThreshold
airportSortKeyThreshold
naturalSortKeyThreshold
districtSortKeyThreshold
citySortKeyThreshold
smallSettlementSortKeyThreshold
poiSortKeyThreshold
```

Keep helpers that are still used by road labels, fallback water labels, geometry parsing, or extrusion parsing.

- [ ] **Step 3: Run parser-focused search**

Run:

```bash
rg -n "TileLabelTextResolver|resolveLabelText|resolveHouseNumberText" ImmersiveMap
```

Expected: `TileLabelTextResolver` may still be used by road labels. If it is used only for road labels, keep it until road-label migration.

- [ ] **Step 4: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Run source header check for new Swift files**

Run:

```bash
for file in ImmersiveMap/VectorTileAdaptation/Labels/**/*.swift Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift; do head -n 2 "$file"; done
```

Expected: every printed pair starts with:

```text
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT
```

- [ ] **Step 6: Commit cleanup**

Run:

```bash
git add ImmersiveMap/Tile/Parse ImmersiveMap/VectorTileAdaptation Tests/ImmersiveMapTests/VectorTileLabelDecisionEngineTests.swift
git commit -m "refactor: clean up migrated point label decisions"
```

---

## Self-Review

- Spec coverage: the plan creates the internal `VectorTileAdaptation/Labels` structure, isolates provider-specific Mapbox point-label decisions, keeps public API unchanged, preserves the existing runtime renderer pipeline, and adds non-Metal tests for identity, language fallback, visibility, and priority.
- Scope check: road labels, Metal buffers, renderer caches, public configuration, and network provider concerns remain outside this plan.
- Type consistency: all planned type names use the `VectorTileLabel` prefix and are referenced consistently by the parser integration task.

