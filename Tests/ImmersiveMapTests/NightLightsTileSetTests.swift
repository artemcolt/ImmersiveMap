// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class NightLightsTileSetTests: XCTestCase {
    func testMetadataDecodesFromJSON() throws {
        let json = """
        {
            "version": 1,
            "format": "jpg",
            "tileSize": 1024,
            "minZoom": 4,
            "maxZoom": 6,
            "source": "NASA Black Marble 2016",
            "attribution": "NASA Earth Observatory"
        }
        """

        let metadata = try JSONDecoder().decode(NightLightsTileSet.Metadata.self, from: Data(json.utf8))

        XCTAssertEqual(metadata.version, 1)
        XCTAssertEqual(metadata.format, "jpg")
        XCTAssertEqual(metadata.tileSize, 1024)
        XCTAssertEqual(metadata.minZoom, 4)
        XCTAssertEqual(metadata.maxZoom, 6)
        XCTAssertEqual(metadata.source, "NASA Black Marble 2016")
        XCTAssertEqual(metadata.attribution, "NASA Earth Observatory")
    }

    func testBestAvailableTileClampsZoomToMetadataRange() {
        let tileSet = makeTileSet()

        XCTAssertEqual(tileSet.bestAvailableTile(for: Tile(x: 1, y: 1, z: 2)),
                       Tile(x: 4, y: 4, z: 4))
        XCTAssertEqual(tileSet.bestAvailableTile(for: Tile(x: 25, y: 35, z: 6)),
                       Tile(x: 25, y: 35, z: 6))
        XCTAssertEqual(tileSet.bestAvailableTile(for: Tile(x: 101, y: 142, z: 8)),
                       Tile(x: 25, y: 35, z: 6))
    }

    func testMappingReturnsNilWhenRequestedZoomIsBelowMinimumZoom() {
        let tileSet = makeTileSet()

        XCTAssertNil(tileSet.mapping(for: Tile(x: 1, y: 1, z: 2)))
    }

    func testMappingReturnsSourceTileAndRelativeUVsForLowerZoomSource() throws {
        let tileSet = makeTileSet()

        let mapping = try XCTUnwrap(tileSet.mapping(for: Tile(x: 101, y: 142, z: 8)))

        XCTAssertEqual(mapping.tile, Tile(x: 25, y: 35, z: 6))
        XCTAssertEqual(mapping.uvOrigin.x, Float(0.25), accuracy: Float(0.0001))
        XCTAssertEqual(mapping.uvOrigin.y, Float(0.50), accuracy: Float(0.0001))
        XCTAssertEqual(mapping.uvScale.x, Float(0.25), accuracy: Float(0.0001))
        XCTAssertEqual(mapping.uvScale.y, Float(0.25), accuracy: Float(0.0001))
    }

    func testInitLoadsMetadataFromSupportedBundleResourcePaths() throws {
        let rootBundle = try makeBundle(resourceRoot: "", metadataFileName: "night_lights_tiles_metadata")
        let directBundle = try makeBundle(resourceRoot: "NightLightsTiles")
        let processedBundle = try makeBundle(resourceRoot: "Render/EarthScene/Resources/NightLightsTiles")

        XCTAssertEqual(try NightLightsTileSet(bundle: rootBundle).metadata, makeMetadata())
        XCTAssertEqual(try NightLightsTileSet(bundle: directBundle).metadata, makeMetadata())
        XCTAssertEqual(try NightLightsTileSet(bundle: processedBundle).metadata, makeMetadata())
    }

    func testRootGenericMetadataFileDoesNotShadowUniqueMetadataFile() throws {
        let bundle = try makeBundle(resourceRoot: "", metadataFileName: "night_lights_tiles_metadata")
        try """
        {
            "version": 999,
            "format": "png",
            "tileSize": 1,
            "minZoom": 0,
            "maxZoom": 0,
            "source": "wrong",
            "attribution": "wrong"
        }
        """.write(to: bundle.bundleURL.appendingPathComponent("metadata.json"),
                  atomically: true,
                  encoding: .utf8)

        XCTAssertEqual(try NightLightsTileSet(bundle: bundle).metadata, makeMetadata())
    }

    func testURLResolvesProcessedResourceTilePath() throws {
        let bundle = try makeBundle(resourceRoot: "Render/EarthScene/Resources/NightLightsTiles")
        let tileSet = NightLightsTileSet(metadata: makeMetadata(), bundle: bundle)

        let url = try XCTUnwrap(tileSet.url(for: Tile(x: 101, y: 142, z: 8)))

        XCTAssertTrue(url.path.hasSuffix("Render/EarthScene/Resources/NightLightsTiles/6/25/35.jpg"))
    }

    func testURLResolvesFlatGeneratedTileNameBeforeDirectoryFallbacks() throws {
        let bundle = try makeBundle(resourceRoot: "Render/EarthScene/Resources/NightLightsTiles")
        let flatURL = bundle.bundleURL.appendingPathComponent("night_lights_6_25_35.jpg")
        try Data([1]).write(to: flatURL)
        let tileSet = NightLightsTileSet(metadata: makeMetadata(), bundle: bundle)

        let url = try XCTUnwrap(tileSet.url(for: Tile(x: 101, y: 142, z: 8)))

        XCTAssertEqual(url.lastPathComponent, "night_lights_6_25_35.jpg")
    }

    private func makeTileSet() -> NightLightsTileSet {
        NightLightsTileSet(metadata: makeMetadata())
    }

    private func makeMetadata() -> NightLightsTileSet.Metadata {
        NightLightsTileSet.Metadata(version: 1,
                                    format: "jpg",
                                    tileSize: 1024,
                                    minZoom: 4,
                                    maxZoom: 6,
                                    source: "NASA Black Marble 2016",
                                    attribution: "NASA Earth Observatory")
    }

    private func makeBundle(resourceRoot: String,
                            metadataFileName: String = "night_lights_tiles_metadata") throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("bundle")
        let resourceDirectory = resourceRoot.isEmpty
            ? directory
            : directory.appendingPathComponent(resourceRoot, isDirectory: true)
        let tileDirectory = resourceDirectory
            .appendingPathComponent("6", isDirectory: true)
            .appendingPathComponent("25", isDirectory: true)

        try FileManager.default.createDirectory(at: tileDirectory, withIntermediateDirectories: true)
        try metadataJSON.write(to: resourceDirectory.appendingPathComponent("\(metadataFileName).json"),
                               atomically: true,
                               encoding: .utf8)
        try Data().write(to: tileDirectory.appendingPathComponent("35.jpg"))

        let bundleIdentifier = "com.immersivemap.tests.nightlights.\(UUID().uuidString)"
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(bundleIdentifier)</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: directory.appendingPathComponent("Info.plist"),
                            atomically: true,
                            encoding: .utf8)

        return try XCTUnwrap(Bundle(url: directory))
    }

    private var metadataJSON: String {
        """
        {
            "version": 1,
            "format": "jpg",
            "tileSize": 1024,
            "minZoom": 4,
            "maxZoom": 6,
            "source": "NASA Black Marble 2016",
            "attribution": "NASA Earth Observatory"
        }
        """
    }
}
