// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import Metal
import XCTest

final class NightLightsTextureTests: XCTestCase {
    func testPlaceholderTextureReturnsFallbackWithoutAttemptingLoad() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is unavailable")
        }

        let bundle = try makeEmptyBundle()
        let nightLightsTexture = NightLightsTexture(device: device, bundle: bundle)

        let texture = nightLightsTexture.placeholderTexture

        XCTAssertEqual(texture.width, 1)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(texture.pixelFormat, .r8Unorm)
        XCTAssertEqual(texture.label, "NightLightsTextureFallback")
        XCTAssertNil(nightLightsTexture.loadErrorDescription)
    }

    func testMissingBundledResourceReturnsFallbackTextureAndRecordsError() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is unavailable")
        }

        let bundle = try makeEmptyBundle()
        let nightLightsTexture = NightLightsTexture(device: device, bundle: bundle)

        XCTAssertNil(nightLightsTexture.loadErrorDescription)

        let texture = nightLightsTexture.texture()

        XCTAssertEqual(texture.width, 1)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(texture.pixelFormat, .r8Unorm)
        XCTAssertEqual(texture.label, "NightLightsTextureFallback")
        XCTAssertNotNil(nightLightsTexture.loadErrorDescription)
    }

    func testConcurrentMissingResourceAccessReturnsFallbackTexture() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device is unavailable")
        }

        let bundle = try makeEmptyBundle()
        let nightLightsTexture = NightLightsTexture(device: device, bundle: bundle)
        let queue = DispatchQueue(label: "NightLightsTextureTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var textures: [MTLTexture] = []

        for _ in 0..<32 {
            group.enter()
            queue.async {
                let texture = nightLightsTexture.texture()
                resultLock.lock()
                textures.append(texture)
                resultLock.unlock()
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5.0), .success)
        XCTAssertEqual(textures.count, 32)
        XCTAssertTrue(textures.allSatisfy { $0 === nightLightsTexture.placeholderTexture })
        XCTAssertNotNil(nightLightsTexture.loadErrorDescription)
    }

    private func makeEmptyBundle() throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.immersivemap.tests.empty</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: directory.appendingPathComponent("Info.plist"),
                            atomically: true,
                            encoding: .utf8)

        guard let bundle = Bundle(url: directory) else {
            XCTFail("Failed to create empty test bundle")
            throw CocoaError(.fileNoSuchFile)
        }
        return bundle
    }
}
