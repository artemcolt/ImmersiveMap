// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import simd
import XCTest

final class TerrainMeshBuilderTests: XCTestCase {
    func testFlatMeshUsesResolutionSquaredVerticesAndGridIndices() {
        let grid = TerrainHeightGrid(width: 2, height: 2, heightsMeters: [0, 10, 20, 30])

        let mesh = TerrainMeshBuilder.buildFlatMesh(tile: Tile(x: 0, y: 0, z: 0),
                                                    heightGrid: grid,
                                                    resolution: 3,
                                                    exaggeration: 2.0,
                                                    heightScale: 0.01)

        XCTAssertEqual(mesh.vertices.count, 9)
        XCTAssertEqual(mesh.indices.count, 24)
        XCTAssertEqual(mesh.vertices.last?.position.z, 0.6)
    }

    func testMeshBuilderClampsResolutionToAtLeastTwo() {
        let grid = TerrainHeightGrid(width: 1, height: 1, heightsMeters: [100])

        let mesh = TerrainMeshBuilder.buildFlatMesh(tile: Tile(x: 0, y: 0, z: 0),
                                                    heightGrid: grid,
                                                    resolution: 1,
                                                    exaggeration: 1.0,
                                                    heightScale: 0.01)

        XCTAssertEqual(mesh.vertices.count, 4)
        XCTAssertEqual(mesh.indices.count, 6)
    }

    func testGlobeMeshMovesVerticesOutwardByHeight() {
        let grid = TerrainHeightGrid(width: 1, height: 1, heightsMeters: [100])

        let mesh = TerrainMeshBuilder.buildGlobeMesh(tile: Tile(x: 0, y: 0, z: 0),
                                                     heightGrid: grid,
                                                     resolution: 2,
                                                     globeRadius: 10,
                                                     exaggeration: 1,
                                                     heightScale: 0.01)

        XCTAssertEqual(mesh.vertices.count, 4)
        XCTAssertTrue(mesh.vertices.allSatisfy { vertex in
            abs(simd_length(vertex.position) - 11) < 0.001
        })
    }
}
