// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImmersiveMap",
    platforms: [
        .iOS(.v18),
        .macCatalyst(.v18)
    ],
    products: [
        .library(
            name: "ImmersiveMap",
            targets: ["ImmersiveMap"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/measuredweighed/SwiftEarcut.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.31.0")
    ],
    targets: [
        .target(
            name: "ImmersiveMap",
            dependencies: [
                "SwiftEarcut",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "ImmersiveMap",
            resources: [
                .process("Avatars/Shaders"),
                .process("Avatars/resources"),
                .process("Globe/Shaders"),
                .process("Labels/Shaders"),
                .process("Labels/Text/resources"),
                .process("Rendering/Compute/TilePoints/TilePointToScreen.metal"),
                .process("Rendering/Debug/Shaders"),
                .process("Rendering/Shaders/Shared/GeoMath.metal"),
                .process("Tile/Shaders"),
                .process("Trees/Shaders"),
                .process("Trees/resources"),
                .copy("Proto/vector_tile.proto")
            ]
        ),
        .testTarget(
            name: "ImmersiveMapTests",
            dependencies: ["ImmersiveMap"],
            path: "Tests/ImmersiveMapTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
