# Render Pass Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current logical `RenderPass` concept with explicit render layers plus real Metal render pass nodes that own attachments, load/store actions, and encoder lifecycle.

**Architecture:** Rename the current `RenderPass` enum to `RenderLayer` because it represents draw layers inside a Metal encoder. Add a new ordered `RenderPassGraph` that produces `RenderPassNode` values for real Metal passes: first `buildingWinner` when flat mode needs it, then `mainDrawable`. Move `MTLRenderPassDescriptor` creation into pass descriptor providers and let `RenderFramePassEncoder` execute nodes in order.

**Tech Stack:** Swift, Metal, `CAMetalLayer`, `MTLRenderCommandEncoder`, Swift Package/Xcode workspace, iOS Simulator build via `xcodebuild`.

---

## File Structure

- Modify `ImmersiveMap/Render/Architecture/Contracts/RenderPass.swift`
  - Rename current logical pass types to layer types: `RenderLayer`, `RenderLayerPlanItem`, `RenderLayerPlanner`.
  - Keep `RenderSkipReason` and `RenderPassAvailability`.
- Modify `ImmersiveMap/Render/Architecture/Contracts/RenderSubsystem.swift`
  - Change subsystem encoding from `encode(pass:...)` to `encode(layer:...)`.
- Modify all `RenderSubsystem` implementations under `ImmersiveMap/Render/Architecture/Subsystems/**`
  - Replace `RenderPass` parameters and guards with `RenderLayer`.
- Modify `ImmersiveMap/Render/Architecture/Diagnostics/FrameDiagnostics.swift`
  - Track layer durations separately from Metal pass durations.
- Create `ImmersiveMap/Render/Architecture/Contracts/RenderPassNode.swift`
  - Define real Metal pass names, descriptor provider protocol, and executable pass node.
- Create `ImmersiveMap/Render/RenderPassGraph.swift`
  - Plan ordered real Metal pass nodes from frame context, settings, drawable, attachments, and render graph availability.
- Create `ImmersiveMap/Render/Architecture/Subsystems/Scene/BuildingWinnerRenderSubsystem.swift`
  - Encode the building winner layer using an already-created encoder.
- Modify `ImmersiveMap/Render/Drawers/RendererSceneDrawer.swift`
  - Split `drawExtrudedWinnerPass(commandBuffer:...)` into `drawExtrudedWinnerLayer(renderEncoder:...)`.
- Modify `ImmersiveMap/Render/Drawers/RendererPassEncoderFactory.swift`
  - Remove or stop using command-buffer-based factory methods after descriptors move to `RenderPassGraph`.
- Modify `ImmersiveMap/Render/RenderGraph.swift`
  - Replace pre-pass lifecycle with layer encoding only.
- Modify `ImmersiveMap/Render/RenderGraphFactory.swift`
  - Register `BuildingWinnerRenderSubsystem` as a normal subsystem.
  - Remove `BuildingWinnerPrePass` from graph construction.
- Delete `ImmersiveMap/Render/Architecture/Contracts/RenderFramePrePass.swift`
- Delete `ImmersiveMap/Render/Architecture/Subsystems/Scene/BuildingWinnerPrePass.swift`
- Modify `ImmersiveMap/Render/RenderFramePassEncoder.swift`
  - Execute real pass nodes, creating and ending one `MTLRenderCommandEncoder` per node.

---

### Task 1: Rename Logical RenderPass To RenderLayer

**Files:**
- Modify: `ImmersiveMap/Render/Architecture/Contracts/RenderPass.swift`
- Modify: `ImmersiveMap/Render/Architecture/Contracts/RenderSubsystem.swift`
- Modify: `ImmersiveMap/Render/Architecture/Diagnostics/FrameDiagnostics.swift`
- Modify: `ImmersiveMap/Render/RenderGraph.swift`
- Modify: `ImmersiveMap/Render/RenderFramePassEncoder.swift`
- Modify: every file matching `ImmersiveMap/Render/Architecture/Subsystems/**/*.swift`

- [ ] **Step 1: Run structural baseline search**

Run:

```bash
rg -n "RenderPass|RenderPassPlanner|RenderPassPlanItem|encode\\(pass:" ImmersiveMap/Render ImmersiveMap/Render -S
```

Expected: current code references the old logical pass names in contracts, diagnostics, graph, encoder, and subsystem implementations.

- [ ] **Step 2: Rename the logical enum and planner**

In `ImmersiveMap/Render/Architecture/Contracts/RenderPass.swift`, replace the current logical pass declarations with:

```swift
enum RenderLayer: String, CaseIterable {
    case scene
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
        [
            RenderLayerPlanItem(layer: .scene, enabled: true, skipReason: nil),
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

- [ ] **Step 3: Update subsystem contract**

In `ImmersiveMap/Render/Architecture/Contracts/RenderSubsystem.swift`, change the encode signature to:

```swift
func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext)
```

- [ ] **Step 4: Update subsystem registry**

In `ImmersiveMap/Render/Architecture/Subsystems/Infrastructure/RenderSubsystemRegistry.swift`, change:

```swift
func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
    for subsystem in subsystems {
        subsystem.encode(layer: layer, encoder: encoder, frameContext: frameContext)
    }
}
```

- [ ] **Step 5: Update all subsystem implementations**

For each subsystem implementation, change `encode(pass: RenderPass, ...)` to `encode(layer: RenderLayer, ...)` and update guards. Examples:

```swift
func encode(layer: RenderLayer, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
    guard layer == .labels else {
        return
    }
    // existing body unchanged
}
```

For no-op subsystem methods:

```swift
func encode(layer _: RenderLayer, encoder _: MTLRenderCommandEncoder, frameContext _: FrameContext) {}
```

- [ ] **Step 6: Update diagnostics terminology**

In `ImmersiveMap/Render/Architecture/Diagnostics/FrameDiagnostics.swift`, rename `passDurations` to `layerDurations` and `recordPass` to `recordLayer`:

```swift
private(set) var layerDurations: [RenderLayer: TimeInterval] = [:]

func recordLayer(_ layer: RenderLayer, duration: TimeInterval) {
    layerDurations[layer] = duration
}
```

Update `summaryLine()` to print layer durations using the new property name.

- [ ] **Step 7: Update graph and encoder call sites**

In `ImmersiveMap/Render/RenderGraph.swift`:

```swift
func encode(layer: RenderLayer,
            encoder: MTLRenderCommandEncoder,
            frameContext: FrameContext) {
    registry.encode(layer: layer,
                    encoder: encoder,
                    frameContext: frameContext)
}
```

In `ImmersiveMap/Render/RenderFramePassEncoder.swift`, temporarily keep the same single Metal encoder behavior but use:

```swift
let layerPlan = RenderLayerPlanner.plan(availability: passAvailability)
```

and call:

```swift
renderGraph.encode(layer: planItem.layer,
                   encoder: renderEncoder,
                   frameContext: frameContext)
frameContext.diagnostics.recordLayer(planItem.layer,
                                     duration: CACurrentMediaTime() - layerStart)
```

- [ ] **Step 8: Run structural check**

Run:

```bash
rg -n "RenderPassPlanner|RenderPassPlanItem|encode\\(pass:|recordPass|passDurations" ImmersiveMap/Render ImmersiveMap/Render -S
```

Expected: no matches. Matches for `RenderPassAvailability` are expected and should remain.

- [ ] **Step 9: Build**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 2: Add Real Metal Render Pass Node Types

**Files:**
- Create: `ImmersiveMap/Render/Architecture/Contracts/RenderPassNode.swift`

- [ ] **Step 1: Create pass node contracts**

Create `ImmersiveMap/Render/Architecture/Contracts/RenderPassNode.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore

enum RenderPassName: String, CaseIterable {
    case buildingWinner
    case mainDrawable
}

protocol RenderPassDescriptorProvider: AnyObject {
    func makeRenderPassDescriptor(frameContext: FrameContext,
                                  attachments: FrameAttachmentStore,
                                  drawable: CAMetalDrawable?) -> MTLRenderPassDescriptor?
}

struct RenderPassNode {
    let name: RenderPassName
    let descriptorProvider: any RenderPassDescriptorProvider
    let layers: [RenderLayer]
}
```

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: Introduce RenderPassGraph For Ordered Metal Passes

**Files:**
- Create: `ImmersiveMap/Render/RenderPassGraph.swift`

- [ ] **Step 1: Create `RenderPassGraph.swift`**

Create `ImmersiveMap/Render/RenderPassGraph.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import QuartzCore

final class RenderPassGraph {
    private final class BuildingWinnerDescriptorProvider: RenderPassDescriptorProvider {
        func makeRenderPassDescriptor(frameContext: FrameContext,
                                      attachments: FrameAttachmentStore,
                                      drawable _: CAMetalDrawable?) -> MTLRenderPassDescriptor? {
            guard frameContext.renderSurfaceMode == .flat,
                  let winnerIDTexture = attachments.ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
                  let winnerDepthTexture = attachments.ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) else {
                return nil
            }

            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = winnerIDTexture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            descriptor.depthAttachment.texture = winnerDepthTexture
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .dontCare
            descriptor.depthAttachment.clearDepth = 1.0
            return descriptor
        }
    }

    private final class MainDrawableDescriptorProvider: RenderPassDescriptorProvider {
        private let clearColor: MTLClearColor
        private let depthTexture: MTLTexture?

        init(clearColor: MTLClearColor,
             depthTexture: MTLTexture?) {
            self.clearColor = clearColor
            self.depthTexture = depthTexture
        }

        func makeRenderPassDescriptor(frameContext _: FrameContext,
                                      attachments _: FrameAttachmentStore,
                                      drawable: CAMetalDrawable?) -> MTLRenderPassDescriptor? {
            guard let drawable else {
                return nil
            }

            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = drawable.texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = clearColor
            descriptor.colorAttachments[0].storeAction = .store
            if let depthTexture {
                descriptor.depthAttachment.texture = depthTexture
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.storeAction = .dontCare
                descriptor.depthAttachment.clearDepth = 1.0
            }
            return descriptor
        }
    }

    func plan(frameContext: FrameContext,
              settings: ImmersiveMapSettings,
              attachments: FrameAttachmentStore,
              drawable: CAMetalDrawable,
              renderGraph: RenderGraph) -> [RenderPassNode] {
        let resourceRegistry = renderGraph.resourceRegistry
        let depthTexture = attachments.ensureDepthTexture(drawSize: frameContext.drawSize)
        if let depthTexture {
            resourceRegistry.setTexture(depthTexture, named: .depthTexture)
        }

        let clearColor = RenderFrameClearColor.make(transition: frameContext.transition,
                                                    settings: settings)
        let layerAvailability = renderGraph.passAvailability(settings: settings)
        let layerPlan = RenderLayerPlanner.plan(availability: layerAvailability)
            .filter(\.enabled)
            .map(\.layer)

        var nodes: [RenderPassNode] = []
        if frameContext.renderSurfaceMode == .flat {
            nodes.append(RenderPassNode(name: .buildingWinner,
                                        descriptorProvider: BuildingWinnerDescriptorProvider(),
                                        layers: [.buildingWinner]))
        }
        nodes.append(RenderPassNode(name: .mainDrawable,
                                    descriptorProvider: MainDrawableDescriptorProvider(clearColor: clearColor,
                                                                                       depthTexture: depthTexture),
                                    layers: layerPlan))
        return nodes
    }
}
```

- [ ] **Step 2: Add `buildingWinner` layer**

In `ImmersiveMap/Render/Architecture/Contracts/RenderPass.swift`, add:

```swift
case buildingWinner
```

to `RenderLayer`.

Do not add `buildingWinner` to `RenderLayerPlanner.plan`; it is scheduled only by `RenderPassGraph`.

- [ ] **Step 3: Build and expect a compile failure**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: FAIL because no subsystem encodes `.buildingWinner` yet or because exhaustive diagnostics/summary logic needs the new enum case handled.

---

### Task 4: Move Building Winner To A Normal Render Layer

**Files:**
- Create: `ImmersiveMap/Render/Architecture/Subsystems/Scene/BuildingWinnerRenderSubsystem.swift`
- Modify: `ImmersiveMap/Render/Drawers/RendererSceneDrawer.swift`
- Modify: `ImmersiveMap/Render/RenderGraphFactory.swift`
- Delete later: `ImmersiveMap/Render/Architecture/Subsystems/Scene/BuildingWinnerPrePass.swift`

- [ ] **Step 1: Extract winner draw body**

In `ImmersiveMap/Render/Drawers/RendererSceneDrawer.swift`, replace the current `drawExtrudedWinnerPass(commandBuffer:...)` method with:

```swift
static func drawExtrudedWinnerLayer(renderEncoder: MTLRenderCommandEncoder,
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
```

- [ ] **Step 2: Add building winner subsystem**

Create `ImmersiveMap/Render/Architecture/Subsystems/Scene/BuildingWinnerRenderSubsystem.swift`:

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

        RendererSceneDrawer.drawExtrudedWinnerLayer(renderEncoder: encoder,
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

- [ ] **Step 3: Register subsystem in factory**

In `ImmersiveMap/Render/RenderGraphFactory.swift`, replace:

```swift
let buildingWinnerPrePass = BuildingWinnerPrePass(extrudedTilePipeline: context.extrudedTilePipeline,
                                                  extrudedDepthState: context.extrudedDepthState)
```

with:

```swift
let buildingWinnerSubsystem = BuildingWinnerRenderSubsystem(extrudedTilePipeline: context.extrudedTilePipeline,
                                                            extrudedDepthState: context.extrudedDepthState)
```

Add `buildingWinnerSubsystem` to the `subsystems` array before `commonViewSceneSubsystem`.

For now keep the `RenderGraph` initializer pre-pass argument as-is until Task 6 removes it.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: may still fail if old `BuildingWinnerPrePass` references the removed `drawExtrudedWinnerPass`. That failure is expected and will be resolved in Task 6.

---

### Task 5: Execute RenderPassGraph In RenderFramePassEncoder

**Files:**
- Modify: `ImmersiveMap/Render/RenderFramePassEncoder.swift`
- Modify: `ImmersiveMap/Render/Architecture/Diagnostics/FrameDiagnostics.swift`

- [ ] **Step 1: Add pass graph dependency**

In `ImmersiveMap/Render/RenderFramePassEncoder.swift`, add:

```swift
private let passGraph = RenderPassGraph()
```

- [ ] **Step 2: Replace single-encoder workflow with node execution**

Replace the body after drawable acquisition with this structure:

```swift
let passNodes = passGraph.plan(frameContext: frameContext,
                               settings: settings,
                               attachments: attachments,
                               drawable: drawable,
                               renderGraph: renderGraph)

for passNode in passNodes {
    guard let descriptor = passNode.descriptorProvider.makeRenderPassDescriptor(frameContext: frameContext,
                                                                               attachments: attachments,
                                                                               drawable: drawable),
          let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
        continue
    }

    let passStart = CACurrentMediaTime()
    for layer in passNode.layers {
        let layerStart = CACurrentMediaTime()
        renderGraph.encode(layer: layer,
                           encoder: renderEncoder,
                           frameContext: frameContext)
        frameContext.diagnostics.recordLayer(layer,
                                             duration: CACurrentMediaTime() - layerStart)
    }
    renderEncoder.endEncoding()
    frameContext.diagnostics.recordMetalPass(passNode.name,
                                             duration: CACurrentMediaTime() - passStart)
}

return drawable
```

- [ ] **Step 3: Add metal pass diagnostics**

In `ImmersiveMap/Render/Architecture/Diagnostics/FrameDiagnostics.swift`, add:

```swift
private(set) var metalPassDurations: [RenderPassName: TimeInterval] = [:]

func recordMetalPass(_ pass: RenderPassName, duration: TimeInterval) {
    metalPassDurations[pass] = duration
}
```

Update `summaryLine()` to include `metalPassDurations` in a compact form after stage durations and before layer durations.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: compile errors only from obsolete `RenderFramePrePass` / `BuildingWinnerPrePass` references if they still exist.

---

### Task 6: Remove RenderFramePrePass And Old Descriptor Factory Usage

**Files:**
- Modify: `ImmersiveMap/Render/RenderGraph.swift`
- Modify: `ImmersiveMap/Render/RenderGraphFactory.swift`
- Delete: `ImmersiveMap/Render/Architecture/Contracts/RenderFramePrePass.swift`
- Delete: `ImmersiveMap/Render/Architecture/Subsystems/Scene/BuildingWinnerPrePass.swift`
- Modify: `ImmersiveMap/Render/Drawers/RendererPassEncoderFactory.swift`

- [ ] **Step 1: Remove pre-pass storage from RenderGraph**

In `ImmersiveMap/Render/RenderGraph.swift`, remove:

```swift
private let prePasses: [any RenderFramePrePass]
```

Remove the initializer parameter:

```swift
prePasses: [any RenderFramePrePass],
```

Remove these methods:

```swift
func preparePrePasses(frameContext: FrameContext, attachments: FrameAttachmentStore)
func encodePrePasses(commandBuffer: MTLCommandBuffer, frameContext: FrameContext)
```

Remove pre-pass calls from `handleMemoryWarning()` and `evict()`.

- [ ] **Step 2: Update graph factory initializer call**

In `ImmersiveMap/Render/RenderGraphFactory.swift`, change:

```swift
return RenderGraph(registry: RenderSubsystemRegistry(subsystems: subsystems),
                   prePasses: [buildingWinnerPrePass],
                   availabilityProviders: availabilityProviders)
```

to:

```swift
return RenderGraph(registry: RenderSubsystemRegistry(subsystems: subsystems),
                   availabilityProviders: availabilityProviders)
```

- [ ] **Step 3: Delete obsolete files**

Delete:

```text
ImmersiveMap/Render/Architecture/Contracts/RenderFramePrePass.swift
ImmersiveMap/Render/Architecture/Subsystems/Scene/BuildingWinnerPrePass.swift
```

- [ ] **Step 4: Remove obsolete factory methods**

In `ImmersiveMap/Render/Drawers/RendererPassEncoderFactory.swift`, either delete the file if no callers remain, or reduce it to only methods still referenced. Verify with:

```bash
rg -n "RendererPassEncoderFactory|makeRenderEncoder|makeBuildingWinnerEncoder" ImmersiveMap -S
```

Expected: no callers remain after `RenderFramePassEncoder` uses `RenderPassGraph` descriptors directly.

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 7: Publish Winner Textures From RenderPassGraph

**Files:**
- Modify: `ImmersiveMap/Render/RenderPassGraph.swift`

- [ ] **Step 1: Register building winner textures**

In `RenderPassGraph.plan(...)`, before appending the `buildingWinner` node, ensure winner textures are created and published:

```swift
if frameContext.renderSurfaceMode == .flat,
   let winnerIDTexture = attachments.ensureBuildingWinnerIDTexture(drawSize: frameContext.drawSize),
   let winnerDepthTexture = attachments.ensureBuildingWinnerDepthTexture(drawSize: frameContext.drawSize) {
    resourceRegistry.setTexture(winnerIDTexture, named: .buildingWinnerIDTexture)
    resourceRegistry.setTexture(winnerDepthTexture, named: .buildingWinnerDepthTexture)
    nodes.append(RenderPassNode(name: .buildingWinner,
                                descriptorProvider: BuildingWinnerDescriptorProvider(),
                                layers: [.buildingWinner]))
}
```

Keep `BuildingWinnerDescriptorProvider` using `ensure...` as well so descriptor creation is robust if called independently.

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 8: Final Structural Verification

**Files:**
- No edits unless checks fail.

- [ ] **Step 1: Check conceptual naming**

Run:

```bash
rg -n "enum RenderPass|RenderPassPlanner|RenderPassPlanItem|encode\\(pass:|RenderFramePrePass|BuildingWinnerPrePass|makeBuildingWinnerEncoder|makeRenderEncoder" ImmersiveMap/Render ImmersiveMap/Render -S
```

Expected: no matches.

- [ ] **Step 2: Check expected new architecture names**

Run:

```bash
rg -n "RenderLayer|RenderPassNode|RenderPassGraph|RenderPassName|recordMetalPass|recordLayer" ImmersiveMap/Render ImmersiveMap/Render -S
```

Expected: matches in contracts, graph, frame encoder, diagnostics, and subsystem implementations.

- [ ] **Step 3: Check ignored build artifacts**

Run:

```bash
git status --short --ignored
```

Expected: `DerivedData/` appears only under ignored entries (`!! DerivedData/`), not tracked modifications.

- [ ] **Step 4: Final build**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/CodexBuild build
```

Expected: `** BUILD SUCCEEDED **`.

---

## Self-Review

- Spec coverage: The plan renames logical passes to layers, introduces real Metal pass nodes, moves building winner into the normal subsystem model, executes multiple Metal encoders, removes pre-pass compatibility code, and verifies the final architecture.
- Placeholder scan: No placeholder markers or vague catch-all steps remain.
- Type consistency: The plan uses `RenderLayer`, `RenderLayerPlanner`, `RenderPassNode`, `RenderPassGraph`, `RenderPassName`, `recordLayer`, and `recordMetalPass` consistently after Task 1.
