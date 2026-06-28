// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import XCTest

final class AvatarRenderShaderShapeTests: XCTestCase {
    func testAvatarFragmentUsesOnlyMarkerSDFShape() throws {
        let source = try avatarRenderShaderSource()

        XCTAssertFalse(source.contains("circleShape"))
        XCTAssertFalse(source.contains("flags & 2u"))
        XCTAssertTrue(source.contains("decodeSignedDistanceTexels"))
        XCTAssertTrue(source.contains("sdfTexture.sample"))
    }

    private func avatarRenderShaderSource() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shaderURL = packageRootURL.appendingPathComponent("ImmersiveMap/Render/Avatars/Shaders/AvatarRender.metal")
        return try String(contentsOf: shaderURL, encoding: .utf8)
    }
}
