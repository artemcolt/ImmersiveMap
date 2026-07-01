// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import simd
import XCTest

final class TileTextLabelsBuilderTierTests: XCTestCase {
    func testBuildCreatesFullReducedAndMinimalSetsByPriority() {
        let result = TileTextLabelsBuilder.makeTextLabels(from: makeBuiltLabels(count: 11))

        XCTAssertEqual(result.full.placementInputs.count, 11)
        XCTAssertEqual(result.reduced.placementInputs.count, 6)
        XCTAssertEqual(result.minimal.placementInputs.count, 2)
        XCTAssertEqual(result.reduced.placementInputs.map { $0.placementMeta.key }, Array(UInt64(1)...UInt64(6)))
        XCTAssertEqual(result.minimal.placementInputs.map { $0.placementMeta.key }, [UInt64(1), UInt64(2)])
    }

    func testTierVerticesUseCompactLabelIndices() {
        let result = TileTextLabelsBuilder.makeTextLabels(from: makeBuiltLabels(count: 11))
        let minimalIndices = Set(result.minimal.glyphRuns.flatMap { $0.localGlyphVertices }.map { Int($0.labelIndex) })

        XCTAssertEqual(minimalIndices, [0, 1])
    }

    private func makeBuiltLabels(count: Int) -> [TileTextLabelsBuilder.BuiltBaseLabel] {
        let style = LabelTextStyle(key: 1,
                                   fillColor: SIMD3<Float>(1, 1, 1),
                                   strokeColor: SIMD3<Float>(0, 0, 0),
                                   strokeWidthPx: 1,
                                   sizePx: 12,
                                   weight: .thin)
        return (0..<count).map { index in
            TileTextLabelsBuilder.BuiltBaseLabel(
                placementInput: TextLabelPlacementInput(
                    pointInput: TilePointInput(uv: SIMD2<Float>(Float(index), Float(index)),
                                               tile: SIMD3<Int32>(1, 2, 4),
                                               tileSlotIndex: 0),
                    placementMeta: LabelPlacementMeta(key: UInt64(index + 1),
                                                      sortKey: index,
                                                      collisionPriority: index,
                                                      labelSizePx: SIMD2<Float>(10, 4))
                ),
                style: style,
                textVertices: [
                    LabelVertex(position: SIMD2<Float>(0, 0),
                                uv: SIMD2<Float>(0, 0),
                                labelIndex: simd_int1(index),
                                spriteUV: SIMD2<Float>(0, 0))
                ],
                iconVertices: []
            )
        }
    }
}
