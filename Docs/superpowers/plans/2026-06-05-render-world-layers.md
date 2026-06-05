# Render World Layers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generic `RenderLayer.scene` path with concrete world render layers and specific world subsystems while preserving flat and globe visual output.

**Architecture:** Keep the existing Metal pass model: `buildingWinner` remains an offscreen pass and `mainDrawable` remains the drawable pass. Make `RenderLayerPlanner` mode-aware using the existing `ViewMode` type, then split the broad scene subsystems into focused `World` subsystems that encode only their own layers.

**Tech Stack:** Swift 6 package, XCTest, Metal, SwiftPM, Xcode host apps.

---

## File Structure

Create:

- `Tests/ImmersiveMapTests/RenderLayerPlannerTests.swift`: unit tests for flat/globe layer ordering and overlay enablement.
- `ImmersiveMap/Render/Core/Subsystems/World/FlatMapSurfaceRenderSubsystem.swift`: encodes flat tile geometry on `.flatMapSurface`.
- `ImmersiveMap/Render/Core/Subsystems/World/BuildingExtrusionRenderSubsystem.swift`: encodes flat-mode building color pass on `.buildingExtrusion`.
- `ImmersiveMap/Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift`: encodes globe-mode starfield on `.starfield`.
- `ImmersiveMap/Render/Core/Subsystems/World/GlobeSurfaceRenderSubsystem.swift`: encodes globe mesh and tile texture on `.globeSurface`.
- `ImmersiveMap/Render/Core/Subsystems/World/GlobeCapRenderSubsystem.swift`: encodes globe cap on `.globeCap`.
- `ImmersiveMap/Render/Tiles/Drawers/FlatMapSurfaceDrawer.swift`: flat tile geometry draw helper.
- `ImmersiveMap/Render/Tiles/Drawers/BuildingExtrusionDrawer.swift`: building extrusion draw helper for color and winner passes.
- `ImmersiveMap/Render/Globe/Drawers/GlobeSurfaceDrawer.swift`: globe surface draw helper.

Modify:

- `ImmersiveMap/Render/Core/Contracts/RenderPass.swift`: replace `.scene` with concrete world layers and make planning mode-aware.
- `ImmersiveMap/Render/Core/Contracts/RenderPassAvailabilityProvider.swift`: initialize availability builder with `ViewMode`.
- `ImmersiveMap/Render/Core/RenderGraph.swift`: pass `ViewMode` into pass availability.
- `ImmersiveMap/Render/Core/RenderPassGraph.swift`: request availability for `frameContext.renderSurfaceMode`.
- `ImmersiveMap/Render/RenderFramePassEncoder.swift`: request availability for `frameContext.renderSurfaceMode` when recording disabled layers.
- `ImmersiveMap/Render/Core/RenderGraphFactory.swift`: register world subsystems in render order.
- `ImmersiveMap/Render/Core/Subsystems/World/BuildingWinnerRenderSubsystem.swift`: move from `Scene` to `World` and call `BuildingExtrusionDrawer`.

Delete:

- `ImmersiveMap/Render/Core/Subsystems/Scene/CommonViewSceneRenderSubsystem.swift`
- `ImmersiveMap/Render/Core/Subsystems/Scene/FlatViewSceneRenderSubsystem.swift`
- `ImmersiveMap/Render/Core/Subsystems/Scene/GlobeViewSceneRenderSubsystem.swift`
- `ImmersiveMap/Render/Core/Subsystems/Scene/BuildingWinnerRenderSubsystem.swift` after moving it to `World`
- `ImmersiveMap/Render/Scene/RendererSceneDrawer.swift` after its draw methods are split

---

### Task 1: Add RenderLayerPlanner Tests

**Files:**
- Create: `Tests/ImmersiveMapTests/RenderLayerPlannerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ImmersiveMapTests/RenderLayerPlannerTests.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import XCTest

final class RenderLayerPlannerTests: XCTestCase {
    func testFlatModePlansWorldLayersBeforeEnabledOverlays() {
        let plan = RenderLayerPlanner.plan(
            availability: RenderPassAvailability(renderSurfaceMode: .flat,
                                                 labelsEnabled: true,
                                                 avatarsEnabled: true,
                                                 debugOverlayEnabled: true)
        )

        XCTAssertEqual(plan.map(\.layer), [
            .flatMapSurface,
            .buildingExtrusion,
            .labels,
            .avatars,
            .debugOverlay
        ])
        XCTAssertTrue(plan.allSatisfy(\.enabled))
        XCTAssertFalse(plan.map(\.layer).contains(.buildingWinner))
    }

    func testFlatModeKeepsOverlayPlanItemsDisabledWhenUnavailable() {
        let plan = RenderLayerPlanner.plan(
            availability: RenderPassAvailability(renderSurfaceMode: .flat,
                                                 labelsEnabled: false,
                                                 avatarsEnabled: false,
                                                 debugOverlayEnabled: false)
        )

        XCTAssertEqual(plan.map(\.layer), [
            .flatMapSurface,
            .buildingExtrusion,
            .labels,
            .avatars,
            .debugOverlay
        ])
        XCTAssertEqual(enabledLayers(in: plan), [.flatMapSurface, .buildingExtrusion])
        XCTAssertEqual(skipReason(for: .labels, in: plan), .noLabelContent)
        XCTAssertEqual(skipReason(for: .avatars, in: plan), .noAvatarContent)
        XCTAssertEqual(skipReason(for: .debugOverlay, in: plan), .debugOverlayDisabled)
    }

    func testGlobeModePlansWorldLayersBeforeEnabledOverlays() {
        let plan = RenderLayerPlanner.plan(
            availability: RenderPassAvailability(renderSurfaceMode: .spherical,
                                                 labelsEnabled: true,
                                                 avatarsEnabled: true,
                                                 debugOverlayEnabled: true)
        )

        XCTAssertEqual(plan.map(\.layer), [
            .starfield,
            .globeSurface,
            .globeCap,
            .labels,
            .avatars,
            .debugOverlay
        ])
        XCTAssertTrue(plan.allSatisfy(\.enabled))
        XCTAssertFalse(plan.map(\.layer).contains(.buildingWinner))
    }

    func testGlobeModeKeepsOverlayPlanItemsDisabledWhenUnavailable() {
        let plan = RenderLayerPlanner.plan(
            availability: RenderPassAvailability(renderSurfaceMode: .spherical,
                                                 labelsEnabled: false,
                                                 avatarsEnabled: false,
                                                 debugOverlayEnabled: false)
        )

        XCTAssertEqual(plan.map(\.layer), [
            .starfield,
            .globeSurface,
            .globeCap,
            .labels,
            .avatars,
            .debugOverlay
        ])
        XCTAssertEqual(enabledLayers(in: plan), [.starfield, .globeSurface, .globeCap])
        XCTAssertEqual(skipReason(for: .labels, in: plan), .noLabelContent)
        XCTAssertEqual(skipReason(for: .avatars, in: plan), .noAvatarContent)
        XCTAssertEqual(skipReason(for: .debugOverlay, in: plan), .debugOverlayDisabled)
    }

    private func enabledLayers(in plan: [RenderLayerPlanItem]) -> [RenderLayer] {
        plan.filter(\.enabled).map(\.layer)
    }

    private func skipReason(for layer: RenderLayer,
                            in plan: [RenderLayerPlanItem]) -> RenderSkipReason? {
        plan.first { $0.layer == layer }?.skipReason
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter RenderLayerPlannerTests
```

Expected: FAIL because `RenderPassAvailability` has no `renderSurfaceMode`, and `RenderLayer` has no concrete world layer cases.

---

### Task 2: Implement Mode-Aware Render Layers

**Files:**
- Modify: `ImmersiveMap/Render/Core/Contracts/RenderPass.swift`
- Modify: `ImmersiveMap/Render/Core/Contracts/RenderPassAvailabilityProvider.swift`
- Modify: `ImmersiveMap/Render/Core/RenderGraph.swift`
- Modify: `ImmersiveMap/Render/Core/RenderPassGraph.swift`
- Modify: `ImmersiveMap/Render/RenderFramePassEncoder.swift`

- [ ] **Step 1: Replace render layer and planner definitions**

In `ImmersiveMap/Render/Core/Contracts/RenderPass.swift`, replace `RenderLayer`, `RenderPassAvailability`, `RenderLayerPlanItem`, and `RenderLayerPlanner` with:

```swift
enum RenderLayer: String, CaseIterable {
    case buildingWinner
    case starfield
    case globeSurface
    case globeCap
    case flatMapSurface
    case buildingExtrusion
    case labels
    case avatars
    case debugOverlay
}

enum RenderSkipReason: String, CaseIterable, Hashable {
    case zeroDrawableSize
    case missingScreenMatrix
    case missingCameraState
    case inFlightSlotsExhausted
    case missingDrawable
    case missingCommandBuffer
    case flatTileOriginUnavailable
    case noLabelContent
    case noAvatarContent
    case debugOverlayDisabled
}

struct RenderPassAvailability {
    let renderSurfaceMode: ViewMode
    let labelsEnabled: Bool
    let avatarsEnabled: Bool
    let debugOverlayEnabled: Bool
}

struct RenderLayerPlanItem {
    let layer: RenderLayer
    let enabled: Bool
    let skipReason: RenderSkipReason?
}

struct RenderLayerPlanner {
    static func plan(availability: RenderPassAvailability) -> [RenderLayerPlanItem] {
        worldPlanItems(for: availability.renderSurfaceMode) + overlayPlanItems(availability: availability)
    }

    private static func worldPlanItems(for renderSurfaceMode: ViewMode) -> [RenderLayerPlanItem] {
        switch renderSurfaceMode {
        case .flat:
            return [
                RenderLayerPlanItem(layer: .flatMapSurface, enabled: true, skipReason: nil),
                RenderLayerPlanItem(layer: .buildingExtrusion, enabled: true, skipReason: nil)
            ]
        case .spherical:
            return [
                RenderLayerPlanItem(layer: .starfield, enabled: true, skipReason: nil),
                RenderLayerPlanItem(layer: .globeSurface, enabled: true, skipReason: nil),
                RenderLayerPlanItem(layer: .globeCap, enabled: true, skipReason: nil)
            ]
        }
    }

    private static func overlayPlanItems(availability: RenderPassAvailability) -> [RenderLayerPlanItem] {
        [
            RenderLayerPlanItem(layer: .labels,
                                enabled: availability.labelsEnabled,
                                skipReason: availability.labelsEnabled ? nil : .noLabelContent),
            RenderLayerPlanItem(layer: .avatars,
                                enabled: availability.avatarsEnabled,
                                skipReason: availability.avatarsEnabled ? nil : .noAvatarContent),
            RenderLayerPlanItem(layer: .debugOverlay,
                                enabled: availability.debugOverlayEnabled,
                                skipReason: availability.debugOverlayEnabled ? nil : .debugOverlayDisabled)
        ]
    }
}
```

- [ ] **Step 2: Update availability builder**

In `ImmersiveMap/Render/Core/Contracts/RenderPassAvailabilityProvider.swift`, replace `RenderPassAvailabilityBuilder` with:

```swift
struct RenderPassAvailabilityBuilder {
    var renderSurfaceMode: ViewMode
    var labelsEnabled: Bool = false
    var avatarsEnabled: Bool = false
    var debugOverlayEnabled: Bool = false

    init(renderSurfaceMode: ViewMode) {
        self.renderSurfaceMode = renderSurfaceMode
    }

    func build() -> RenderPassAvailability {
        RenderPassAvailability(renderSurfaceMode: renderSurfaceMode,
                               labelsEnabled: labelsEnabled,
                               avatarsEnabled: avatarsEnabled,
                               debugOverlayEnabled: debugOverlayEnabled)
    }
}
```

Keep the existing `RenderPassAvailabilityProvider` protocol signature unchanged.

- [ ] **Step 3: Pass render mode through RenderGraph**

In `ImmersiveMap/Render/Core/RenderGraph.swift`, replace:

```swift
func passAvailability(settings: ImmersiveMapSettings) -> RenderPassAvailability {
    var builder = RenderPassAvailabilityBuilder()
```

with:

```swift
func passAvailability(settings: ImmersiveMapSettings,
                      renderSurfaceMode: ViewMode) -> RenderPassAvailability {
    var builder = RenderPassAvailabilityBuilder(renderSurfaceMode: renderSurfaceMode)
```

Keep the provider loop unchanged.

- [ ] **Step 4: Update RenderPassGraph call site**

In `ImmersiveMap/Render/Core/RenderPassGraph.swift`, replace:

```swift
let layerAvailability = renderGraph.passAvailability(settings: settings)
```

with:

```swift
let layerAvailability = renderGraph.passAvailability(settings: settings,
                                                     renderSurfaceMode: frameContext.renderSurfaceMode)
```

- [ ] **Step 5: Update disabled-layer diagnostics call site**

In `ImmersiveMap/Render/RenderFramePassEncoder.swift`, replace:

```swift
let passAvailability = renderGraph.passAvailability(settings: settings)
```

with:

```swift
let passAvailability = renderGraph.passAvailability(settings: settings,
                                                    renderSurfaceMode: frameContext.renderSurfaceMode)
```

- [ ] **Step 6: Run planner tests**

Run:

```bash
swift test --filter RenderLayerPlannerTests
```

Expected: compile may still fail because existing scene subsystems reference `.scene`. Continue to Task 3 before committing if this happens.

---

### Task 3: Split Flat World Rendering

**Files:**
- Create: `ImmersiveMap/Render/Tiles/Drawers/FlatMapSurfaceDrawer.swift`
- Create: `ImmersiveMap/Render/Tiles/Drawers/BuildingExtrusionDrawer.swift`
- Create: `ImmersiveMap/Render/Core/Subsystems/World/FlatMapSurfaceRenderSubsystem.swift`
- Create: `ImmersiveMap/Render/Core/Subsystems/World/BuildingExtrusionRenderSubsystem.swift`
- Create: `ImmersiveMap/Render/Core/Subsystems/World/BuildingWinnerRenderSubsystem.swift`
- Delete: `ImmersiveMap/Render/Core/Subsystems/Scene/FlatViewSceneRenderSubsystem.swift`
- Delete: `ImmersiveMap/Render/Core/Subsystems/Scene/BuildingWinnerRenderSubsystem.swift`

- [ ] **Step 1: Create FlatMapSurfaceDrawer**

Create `ImmersiveMap/Render/Tiles/Drawers/FlatMapSurfaceDrawer.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import simd

enum FlatMapSurfaceDrawer {
    private struct TileOverviewFadeUniform {
        var overviewAlpha: Float
        var roadAlpha: Float
    }

    static func draw(renderEncoder: MTLRenderCommandEncoder,
                     cameraUniform: CameraUniform,
                     cameraZoom: Double,
                     separateRoadRenderingMinimumZoom: Int,
                     placeTilesContext: PlaceTilesContext,
                     flatRenderState: FlatRenderState,
                     tilePipeline: TilePipeline) {
        tilePipeline.selectPipeline(renderEncoder: renderEncoder)
        var cameraUniformValue = cameraUniform
        var overviewFadeUniform = TileOverviewFadeUniform(
            overviewAlpha: LowZoomOverviewFade.alpha(for: cameraZoom, kind: .overviewFeatures),
            roadAlpha: LowZoomOverviewFade.alpha(for: cameraZoom, kind: .roads)
        )
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setFragmentBytes(&overviewFadeUniform,
                                       length: MemoryLayout<TileOverviewFadeUniform>.stride,
                                       index: 0)

        let usesSeparateRoadRendering = cameraZoom >= Double(separateRoadRenderingMinimumZoom)

        func drawLayer(_ keyPath: KeyPath<TileBuffers, TileBuffers.GeometryLayer>) {
            for placeTile in placeTilesContext.tilePlacements {
                let metalTile = placeTile.metalTile
                drawFlatGeometryLayer(renderEncoder: renderEncoder,
                                      buffers: metalTile.tileBuffers[keyPath: keyPath],
                                      tile: metalTile.tile,
                                      placeIn: placeTile.placeIn,
                                      flatRenderState: flatRenderState)
            }
        }

        drawLayer(\.ground)

        if usesSeparateRoadRendering {
            func drawRoadGroup(_ structureKind: TileMvtParser.RoadStructureKind) {
                for role in [RoadPassRole.shadow, .casing, .fill, .detail] {
                    for placeTile in placeTilesContext.tilePlacements {
                        let metalTile = placeTile.metalTile
                        let structureBucket = metalTile.tileBuffers.roads.bucket(for: structureKind)
                        drawFlatGeometryLayer(renderEncoder: renderEncoder,
                                              buffers: structureBucket.layer(for: role),
                                              tile: metalTile.tile,
                                              placeIn: placeTile.placeIn,
                                              flatRenderState: flatRenderState)
                    }
                }
            }

            drawRoadGroup(.tunnel)
            drawRoadGroup(.ground)
            drawLayer(\.bridgeOverlay)
            drawRoadGroup(.bridge)

            for structureKind in [TileMvtParser.RoadStructureKind.tunnel, .ground, .bridge] {
                for placeTile in placeTilesContext.tilePlacements {
                    let metalTile = placeTile.metalTile
                    let structureBucket = metalTile.tileBuffers.roads.bucket(for: structureKind)
                    drawFlatGeometryLayer(renderEncoder: renderEncoder,
                                          buffers: structureBucket.layer(for: .overlay),
                                          tile: metalTile.tile,
                                          placeIn: placeTile.placeIn,
                                          flatRenderState: flatRenderState)
                }
            }
        } else {
            drawLayer(\.bridgeOverlay)
        }
    }

    private static func drawFlatGeometryLayer(renderEncoder: MTLRenderCommandEncoder,
                                              buffers: TileBuffers.GeometryLayer,
                                              tile: Tile,
                                              placeIn: VisibleTile,
                                              flatRenderState: FlatRenderState) {
        guard buffers.indicesCount > 0 else { return }

        let originAndSize = ImmersiveMapProjection.flatTileOriginAndSize(x: tile.x,
                                                                         y: tile.y,
                                                                         z: tile.z,
                                                                         loop: placeIn.loop,
                                                                         flatRenderPan: flatRenderState.pan,
                                                                         renderMapSize: flatRenderState.renderMapSize)
        let scale = originAndSize.z / 4096.0

        renderEncoder.setVertexBuffer(buffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(buffers.stylesBuffer, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(buffers.overviewStyleMaskBuffer, offset: 0, index: 4)

        var modelMatrix = Matrix.translationMatrix(
            x: originAndSize.x,
            y: originAndSize.y,
            z: 0
        ) * Matrix.scaleMatrix(sx: scale, sy: scale, sz: 1)
        renderEncoder.setVertexBytes(&modelMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 3)

        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: buffers.indicesCount,
                                            indexType: .uint32,
                                            indexBuffer: buffers.indicesBuffer,
                                            indexBufferOffset: 0)
    }
}
```

- [ ] **Step 2: Create BuildingExtrusionDrawer**

Create `ImmersiveMap/Render/Tiles/Drawers/BuildingExtrusionDrawer.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import simd

enum BuildingExtrusionDrawer {
    private struct ExtrudedLightUniform {
        var direction: SIMD4<Float>
        var color: SIMD4<Float>
        var intensities: SIMD4<Float>
    }

    private struct ExtrudedMaterialUniform {
        var alpha: Float
        var padding: SIMD3<Float> = .zero
    }

    static func drawColorPass(renderEncoder: MTLRenderCommandEncoder,
                              cameraUniform: CameraUniform,
                              placeTilesContext: PlaceTilesContext,
                              flatRenderState: FlatRenderState,
                              buildingExtrusionAlpha: Float,
                              winnerIDTexture: MTLTexture?,
                              extrudedTilePipeline: ExtrudedTilePipeline,
                              extrudedColorPassDepthState: MTLDepthStencilState,
                              depthDisabledState: MTLDepthStencilState) {
        guard let winnerIDTexture else { return }

        var cameraUniformValue = cameraUniform
        renderEncoder.setCullMode(.back)

        extrudedTilePipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setDepthStencilState(extrudedColorPassDepthState)
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setFragmentTexture(winnerIDTexture, index: 0)
        renderEncoder.setFragmentBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)

        let lightDirection = simd_normalize(SIMD3<Float>(-0.4, -0.6, 1.0))
        var lightUniform = ExtrudedLightUniform(
            direction: SIMD4<Float>(lightDirection, 0.0),
            color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0),
            intensities: SIMD4<Float>(0.35, 0.65, 0.2, 24.0)
        )
        var materialUniform = ExtrudedMaterialUniform(alpha: buildingExtrusionAlpha)
        renderEncoder.setFragmentBytes(&lightUniform, length: MemoryLayout<ExtrudedLightUniform>.stride, index: 2)
        renderEncoder.setFragmentBytes(&materialUniform, length: MemoryLayout<ExtrudedMaterialUniform>.stride, index: 3)
        drawExtrudedGeometry(renderEncoder: renderEncoder,
                             placeTilesContext: placeTilesContext,
                             flatRenderState: flatRenderState)

        renderEncoder.setCullMode(.none)
        renderEncoder.setDepthStencilState(depthDisabledState)
    }

    static func drawWinnerLayer(renderEncoder: MTLRenderCommandEncoder,
                                cameraUniform: CameraUniform,
                                placeTilesContext: PlaceTilesContext,
                                flatRenderState: FlatRenderState,
                                extrudedTilePipeline: ExtrudedTilePipeline,
                                extrudedDepthState: MTLDepthStencilState) {
        var cameraUniformValue = cameraUniform
        renderEncoder.setCullMode(.back)
        renderEncoder.setDepthStencilState(extrudedDepthState)
        extrudedTilePipeline.selectWinnerPipeline(renderEncoder: renderEncoder)
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        drawExtrudedGeometry(renderEncoder: renderEncoder,
                             placeTilesContext: placeTilesContext,
                             flatRenderState: flatRenderState)
    }

    private static func drawExtrudedGeometry(renderEncoder: MTLRenderCommandEncoder,
                                             placeTilesContext: PlaceTilesContext,
                                             flatRenderState: FlatRenderState) {
        for placeTile in placeTilesContext.tilePlacements {
            let metalTile = placeTile.metalTile
            let tile = metalTile.tile
            let buffers = metalTile.tileBuffers
            let placeIn = placeTile.placeIn

            guard buffers.extruded.indicesCount > 0 else { continue }

            let originAndSize = ImmersiveMapProjection.flatTileOriginAndSize(x: tile.x,
                                                                             y: tile.y,
                                                                             z: tile.z,
                                                                             loop: placeIn.loop,
                                                                             flatRenderPan: flatRenderState.pan,
                                                                             renderMapSize: flatRenderState.renderMapSize)
            let scale = originAndSize.z / 4096.0

            renderEncoder.setVertexBuffer(buffers.extruded.verticesBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(buffers.extruded.stylesBuffer, offset: 0, index: 2)

            var modelMatrix = Matrix.translationMatrix(
                x: originAndSize.x,
                y: originAndSize.y,
                z: 0
            ) * Matrix.scaleMatrix(sx: scale, sy: scale, sz: scale)
            renderEncoder.setVertexBytes(&modelMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 3)

            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: buffers.extruded.indicesCount,
                                                indexType: .uint32,
                                                indexBuffer: buffers.extruded.indicesBuffer,
                                                indexBufferOffset: 0)
        }
    }
}
```

- [ ] **Step 3: Create FlatMapSurfaceRenderSubsystem**

Create `ImmersiveMap/Render/Core/Subsystems/World/FlatMapSurfaceRenderSubsystem.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class FlatMapSurfaceRenderSubsystem: RenderSubsystem {
    let name: String = "FlatMapSurface"

    private let tilePipeline: TilePipeline
    private let separateRoadRenderingMinimumZoom: Int

    init(tilePipeline: TilePipeline,
         separateRoadRenderingMinimumZoom: Int) {
        self.tilePipeline = tilePipeline
        self.separateRoadRenderingMinimumZoom = separateRoadRenderingMinimumZoom
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .flatMapSurface,
              frameContext.renderSurfaceMode == .flat else {
            return
        }

        FlatMapSurfaceDrawer.draw(renderEncoder: encoder,
                                  cameraUniform: frameContext.cameraUniform,
                                  cameraZoom: frameContext.zoom,
                                  separateRoadRenderingMinimumZoom: separateRoadRenderingMinimumZoom,
                                  placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                  flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                  tilePipeline: tilePipeline)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
```

- [ ] **Step 4: Create BuildingExtrusionRenderSubsystem**

Create `ImmersiveMap/Render/Core/Subsystems/World/BuildingExtrusionRenderSubsystem.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class BuildingExtrusionRenderSubsystem: RenderSubsystem {
    let name: String = "BuildingExtrusion"

    private let buildingExtrusionAlpha: Float
    private let buildingWinnerIDTextureProvider: () -> MTLTexture?
    private let extrudedTilePipeline: ExtrudedTilePipeline
    private let extrudedColorPassDepthState: MTLDepthStencilState
    private let depthDisabledState: MTLDepthStencilState

    init(buildingExtrusionAlpha: Float,
         buildingWinnerIDTextureProvider: @escaping () -> MTLTexture?,
         extrudedTilePipeline: ExtrudedTilePipeline,
         extrudedColorPassDepthState: MTLDepthStencilState,
         depthDisabledState: MTLDepthStencilState) {
        self.buildingExtrusionAlpha = buildingExtrusionAlpha
        self.buildingWinnerIDTextureProvider = buildingWinnerIDTextureProvider
        self.extrudedTilePipeline = extrudedTilePipeline
        self.extrudedColorPassDepthState = extrudedColorPassDepthState
        self.depthDisabledState = depthDisabledState
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .buildingExtrusion,
              frameContext.renderSurfaceMode == .flat else {
            return
        }

        BuildingExtrusionDrawer.drawColorPass(renderEncoder: encoder,
                                              cameraUniform: frameContext.cameraUniform,
                                              placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                              flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                              buildingExtrusionAlpha: buildingExtrusionAlpha,
                                              winnerIDTexture: buildingWinnerIDTextureProvider(),
                                              extrudedTilePipeline: extrudedTilePipeline,
                                              extrudedColorPassDepthState: extrudedColorPassDepthState,
                                              depthDisabledState: depthDisabledState)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
```

- [ ] **Step 5: Move BuildingWinnerRenderSubsystem to World**

Create `ImmersiveMap/Render/Core/Subsystems/World/BuildingWinnerRenderSubsystem.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class BuildingWinnerRenderSubsystem: RenderSubsystem {
    let name: String = "BuildingWinner"

    private let extrudedTilePipeline: ExtrudedTilePipeline
    private let extrudedDepthState: MTLDepthStencilState

    init(extrudedTilePipeline: ExtrudedTilePipeline,
         extrudedDepthState: MTLDepthStencilState) {
        self.extrudedTilePipeline = extrudedTilePipeline
        self.extrudedDepthState = extrudedDepthState
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .buildingWinner,
              frameContext.renderSurfaceMode == .flat else {
            return
        }

        BuildingExtrusionDrawer.drawWinnerLayer(renderEncoder: encoder,
                                                cameraUniform: frameContext.cameraUniform,
                                                placeTilesContext: frameContext.sharedState.tilePlacementState.placeTilesContext,
                                                flatRenderState: frameContext.resolvedPresentation.flatRenderState,
                                                extrudedTilePipeline: extrudedTilePipeline,
                                                extrudedDepthState: extrudedDepthState)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
```

- [ ] **Step 6: Delete old flat scene files**

Run:

```bash
rm ImmersiveMap/Render/Core/Subsystems/Scene/FlatViewSceneRenderSubsystem.swift
rm ImmersiveMap/Render/Core/Subsystems/Scene/BuildingWinnerRenderSubsystem.swift
```

Expected: files are removed from the working tree.

---

### Task 4: Split Globe World Rendering

**Files:**
- Create: `ImmersiveMap/Render/Globe/Drawers/GlobeSurfaceDrawer.swift`
- Create: `ImmersiveMap/Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift`
- Create: `ImmersiveMap/Render/Core/Subsystems/World/GlobeSurfaceRenderSubsystem.swift`
- Create: `ImmersiveMap/Render/Core/Subsystems/World/GlobeCapRenderSubsystem.swift`
- Delete: `ImmersiveMap/Render/Core/Subsystems/Scene/GlobeViewSceneRenderSubsystem.swift`
- Delete: `ImmersiveMap/Render/Core/Subsystems/Scene/CommonViewSceneRenderSubsystem.swift`
- Delete: `ImmersiveMap/Render/Scene/RendererSceneDrawer.swift`

- [ ] **Step 1: Create GlobeSurfaceDrawer**

Create `ImmersiveMap/Render/Globe/Drawers/GlobeSurfaceDrawer.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import simd

enum GlobeSurfaceDrawer {
    static func draw(renderEncoder: MTLRenderCommandEncoder,
                     cameraUniform: CameraUniform,
                     globe: GlobeUniform,
                     globePipeline: GlobePipeline,
                     mapSurfaceGridBuffers: MapSurfaceGridBuffers,
                     tilesTexture: GlobeTilesTexture) {
        var cameraUniformValue = cameraUniform
        var globeValue = globe

        globePipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setCullMode(.front)
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBytes(&globeValue, length: MemoryLayout<GlobeUniform>.stride, index: 2)
        renderEncoder.setFragmentTexture(tilesTexture.texture, index: 0)
        renderEncoder.setFragmentBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBuffer(mapSurfaceGridBuffers.verticesBuffer, offset: 0, index: 0)

        for mapping in tilesTexture.tileData {
            var mappingValue = mapping
            renderEncoder.setVertexBytes(&mappingValue,
                                         length: MemoryLayout<GlobeTilesTexture.TileData>.stride,
                                         index: 3)
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: mapSurfaceGridBuffers.indicesCount,
                                                indexType: .uint32,
                                                indexBuffer: mapSurfaceGridBuffers.indicesBuffer,
                                                indexBufferOffset: 0)
        }
    }
}
```

- [ ] **Step 2: Create StarfieldRenderSubsystem**

Create `ImmersiveMap/Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class StarfieldRenderSubsystem: RenderSubsystem {
    let name: String = "Starfield"

    private let starfieldRenderer: StarfieldRenderer

    init(starfieldRenderer: StarfieldRenderer) {
        self.starfieldRenderer = starfieldRenderer
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .starfield,
              frameContext.renderSurfaceMode == .spherical else {
            return
        }

        starfieldRenderer.draw(renderEncoder: encoder,
                               globe: frameContext.globeRenderUniform,
                               cameraView: frameContext.cameraMatrices.view,
                               cameraEye: frameContext.cameraEye,
                               drawSize: frameContext.drawSize,
                               nowTime: Float(frameContext.time))
    }

    func handleMemoryWarning() {}

    func evict() {}
}
```

- [ ] **Step 3: Create GlobeSurfaceRenderSubsystem**

Create `ImmersiveMap/Render/Core/Subsystems/World/GlobeSurfaceRenderSubsystem.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class GlobeSurfaceRenderSubsystem: RenderSubsystem {
    let name: String = "GlobeSurface"

    private let globeDepthState: MTLDepthStencilState
    private let globePipeline: GlobePipeline
    private let mapSurfaceGridBuffers: MapSurfaceGridBuffers
    private let tilesTexture: GlobeTilesTexture

    init(globeDepthState: MTLDepthStencilState,
         globePipeline: GlobePipeline,
         mapSurfaceGridBuffers: MapSurfaceGridBuffers,
         tilesTexture: GlobeTilesTexture) {
        self.globeDepthState = globeDepthState
        self.globePipeline = globePipeline
        self.mapSurfaceGridBuffers = mapSurfaceGridBuffers
        self.tilesTexture = tilesTexture
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .globeSurface,
              frameContext.renderSurfaceMode == .spherical else {
            return
        }

        encoder.setDepthStencilState(globeDepthState)
        GlobeSurfaceDrawer.draw(renderEncoder: encoder,
                                cameraUniform: frameContext.cameraUniform,
                                globe: frameContext.globeRenderUniform,
                                globePipeline: globePipeline,
                                mapSurfaceGridBuffers: mapSurfaceGridBuffers,
                                tilesTexture: tilesTexture)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
```

- [ ] **Step 4: Create GlobeCapRenderSubsystem**

Create `ImmersiveMap/Render/Core/Subsystems/World/GlobeCapRenderSubsystem.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

final class GlobeCapRenderSubsystem: RenderSubsystem {
    let name: String = "GlobeCap"

    private let globeCapDepthState: MTLDepthStencilState
    private let depthDisabledState: MTLDepthStencilState
    private let globeCapRenderer: GlobeCapRenderer

    init(globeCapDepthState: MTLDepthStencilState,
         depthDisabledState: MTLDepthStencilState,
         globeCapRenderer: GlobeCapRenderer) {
        self.globeCapDepthState = globeCapDepthState
        self.depthDisabledState = depthDisabledState
        self.globeCapRenderer = globeCapRenderer
    }

    func update(frameContext _: FrameContext) {}

    func prepareGPU(frameContext _: FrameContext, resourceRegistry _: RenderResourceRegistry) {}

    func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        guard layer == .globeCap,
              frameContext.renderSurfaceMode == .spherical else {
            return
        }

        encoder.setDepthStencilState(globeCapDepthState)
        globeCapRenderer.draw(renderEncoder: encoder,
                              cameraUniform: frameContext.cameraUniform,
                              globe: frameContext.globeRenderUniform)
        encoder.setDepthStencilState(depthDisabledState)
    }

    func handleMemoryWarning() {}

    func evict() {}
}
```

- [ ] **Step 5: Delete old globe scene files and broad drawer**

Run:

```bash
rm ImmersiveMap/Render/Core/Subsystems/Scene/GlobeViewSceneRenderSubsystem.swift
rm ImmersiveMap/Render/Core/Subsystems/Scene/CommonViewSceneRenderSubsystem.swift
rm ImmersiveMap/Render/Scene/RendererSceneDrawer.swift
```

Expected: files are removed from the working tree.

---

### Task 5: Register World Subsystems

**Files:**
- Modify: `ImmersiveMap/Render/Core/RenderGraphFactory.swift`

- [ ] **Step 1: Replace scene subsystem construction**

In `ImmersiveMap/Render/Core/RenderGraphFactory.swift`, replace the existing `buildingWinnerSubsystem`, `commonViewSceneSubsystem`, `globeViewSceneSubsystem`, and `flatViewSceneSubsystem` construction with:

```swift
let buildingWinnerSubsystem = BuildingWinnerRenderSubsystem(extrudedTilePipeline: context.extrudedTilePipeline,
                                                            extrudedDepthState: context.extrudedDepthState)
let flatMapSurfaceSubsystem = FlatMapSurfaceRenderSubsystem(tilePipeline: context.tilePipeline,
                                                            separateRoadRenderingMinimumZoom: settings.style.flatSeparateRoadRenderingMinimumZoom)
let buildingExtrusionSubsystem = BuildingExtrusionRenderSubsystem(buildingExtrusionAlpha: settings.style.buildingExtrusionAlpha,
                                                                  buildingWinnerIDTextureProvider: buildingWinnerIDTextureProvider,
                                                                  extrudedTilePipeline: context.extrudedTilePipeline,
                                                                  extrudedColorPassDepthState: context.extrudedColorPassDepthState,
                                                                  depthDisabledState: context.depthDisabledState)
let starfieldSubsystem = StarfieldRenderSubsystem(starfieldRenderer: context.starfieldRenderer)
let globeSurfaceSubsystem = GlobeSurfaceRenderSubsystem(globeDepthState: context.extrudedDepthState,
                                                        globePipeline: context.globePipeline,
                                                        mapSurfaceGridBuffers: context.mapSurfaceGridBuffers,
                                                        tilesTexture: context.tilesTexture)
let globeCapSubsystem = GlobeCapRenderSubsystem(globeCapDepthState: context.globeCapDepthState,
                                                depthDisabledState: context.depthDisabledState,
                                                globeCapRenderer: context.globeCapRenderer)
```

- [ ] **Step 2: Replace subsystem ordering**

In the `subsystems` array, replace:

```swift
avatarSubsystem,
buildingWinnerSubsystem,
commonViewSceneSubsystem,
globeViewSceneSubsystem,
flatViewSceneSubsystem,
debugSubsystem
```

with:

```swift
avatarSubsystem,
buildingWinnerSubsystem,
flatMapSurfaceSubsystem,
buildingExtrusionSubsystem,
starfieldSubsystem,
globeSurfaceSubsystem,
globeCapSubsystem,
debugSubsystem
```

Expected ordering note: `RenderFramePassEncoder` controls layer order. Registry ordering is still relevant because every subsystem receives each layer, so keeping world subsystems in logical draw order makes diagnostics and debugging easier.

- [ ] **Step 3: Run planner tests**

Run:

```bash
swift test --filter RenderLayerPlannerTests
```

Expected: PASS.

---

### Task 6: Remove Scene References And Build

**Files:**
- Verify: `ImmersiveMap/Render`
- Verify: `Tests/ImmersiveMapTests`

- [ ] **Step 1: Search for stale scene render references**

Run:

```bash
rg -n "RenderLayer\\.scene|case scene|RendererSceneDrawer|CommonViewScene|FlatViewScene|GlobeViewScene|Render/Core/Subsystems/Scene" ImmersiveMap Tests
```

Expected: no matches.

- [ ] **Step 2: Search for old pass availability call sites**

Run:

```bash
rg -n "passAvailability\\(settings:" ImmersiveMap
```

Expected: only call sites that also pass `renderSurfaceMode:` are present.

- [ ] **Step 3: Run full Swift package tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Commit the refactor**

Run:

```bash
git status --short
git add ImmersiveMap Tests
git commit -m "Refactor scene rendering into world layers"
```

Expected: one commit containing source and test changes for the world layer refactor.

---

### Task 7: Host Build And Visual Verification

**Files:**
- Verify: `ImmersiveMap.xcworkspace`
- Verify: `ImmersiveMapMac/ImmersiveMapMac.xcodeproj`
- Verify: `ImmersiveMapIOS/ImmersiveMapIOS.xcodeproj`

- [ ] **Step 1: Build the package**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 2: Build the Mac host app**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapMac -destination 'platform=macOS,variant=Mac Catalyst' build
```

Expected: PASS. If the destination is unavailable on the machine, record the exact `xcodebuild` destination error in the handoff.

- [ ] **Step 3: Build the iOS host app**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: PASS. If the simulator name is unavailable, run `xcrun simctl list devices available` and retry with an available iOS 18+ simulator.

- [ ] **Step 4: Run flat visual smoke check**

Run the Mac or iOS host at a high zoom level.

Expected visual result: flat Moscow city map renders with ground, roads, 3D buildings, labels when available, avatars when available, and no missing base map layer.

- [ ] **Step 5: Run globe visual smoke check**

Run the Mac or iOS host at a low zoom level.

Expected visual result: starfield/background renders behind the globe, globe surface renders with tile texture, globe cap remains visible, labels/avatars render when available, and no depth-state corruption appears after globe cap rendering.

- [ ] **Step 6: Final status check**

Run:

```bash
git status --short --ignored
```

Expected: source tree is clean except ignored build artifacts such as `.build/` or `DerivedData/`.
