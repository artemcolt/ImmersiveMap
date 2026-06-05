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
        XCTAssertEqual(identity.runtimeKey, 17424410298459024603)
        XCTAssertEqual(identity.runtimeKey,
                       VectorTileLabelIdentity.providerFeature(providerID: "mapbox",
                                                               layerName: "place_label",
                                                               featureID: 42).runtimeKey)
    }

    func testSemanticIdentityUsesStableRuntimeKey() {
        let identity = VectorTileLabelIdentity.semantic(providerID: "mapbox",
                                                        kind: "place",
                                                        text: "Moscow",
                                                        worldBucket: SIMD2<Int32>(10, 20))

        XCTAssertTrue(identity.participatesInCrossTileDeduplication)
        XCTAssertEqual(identity.runtimeKey, 18093230200447490384)
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
        XCTAssertEqual(first.runtimeKey, 6949302229354522716)
        XCTAssertEqual(second.runtimeKey, 6830255165424541913)
        XCTAssertNotEqual(first.runtimeKey, second.runtimeKey)
    }
}
