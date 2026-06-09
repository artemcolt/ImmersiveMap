# Cinematic Sun Object Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an astronomical visible Sun object to the spherical globe scene with a glowing disk, edge glare, and cinematic limb halo.

**Architecture:** Extend the existing Earth scene settings/uniform path, then render the Sun from the starfield subsystem before globe surface/cap drawing. CPU-side code computes a small shader-facing visual state from the astronomical `sunDirection`; Metal draws a full-screen additive Sun pass using that state.

**Tech Stack:** Swift Package, XCTest, Metal, Swift simd, existing `StarfieldRenderer`, `StarfieldPipeline`, `EarthSceneUniform`, and `RenderUniforms.h`.

---

## Current Context

The implementation should be done in a fresh isolated worktree from `main`. The main checkout currently has unrelated dirty/untracked files; do not edit or revert them.

Relevant existing files:

- `ImmersiveMap/Configuration/ImmersiveMapSettings.swift`: public settings and defaults.
- `ImmersiveMap/EarthScene/EarthSceneUniform.swift`: Swift shader-facing Earth scene data.
- `ImmersiveMap/Render/Shaders/Shared/RenderUniforms.h`: Metal ABI mirror for `EarthScene`.
- `ImmersiveMap/Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift`: spherical-only starfield entry point.
- `ImmersiveMap/Render/Starfield/StarfieldRenderer.swift`: background and stars renderer.
- `ImmersiveMap/Render/Starfield/StarfieldPipeline.swift`: starfield render pipeline states.
- `ImmersiveMap/Render/Shaders/Starfield/StarfieldStars.metal`: background and star shaders.

## File Structure

Create:

- `ImmersiveMap/EarthScene/EarthSceneSunVisualState.swift`: CPU helper that converts `EarthSceneUniform.sunDirection` into shader-facing Sun visibility, screen position, and glare/halo factors.
- `Tests/ImmersiveMapTests/EarthSceneSunVisualStateTests.swift`: deterministic tests for projection and occlusion classification.

Modify:

- `ImmersiveMap/Configuration/ImmersiveMapSettings.swift`: add nested `EarthSceneSettings.SunSettings` and default values.
- `ImmersiveMap/EarthScene/EarthSceneUniform.swift`: add shader-facing Sun visual controls.
- `ImmersiveMap/Render/Shaders/Shared/RenderUniforms.h`: mirror the expanded `EarthScene` ABI.
- `ImmersiveMap/Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift`: pass Earth scene uniform to `StarfieldRenderer`.
- `ImmersiveMap/Render/Starfield/StarfieldRenderer.swift`: compute visual state and encode the Sun pass.
- `ImmersiveMap/Render/Starfield/StarfieldPipeline.swift`: add a Sun additive pipeline state.
- `ImmersiveMap/Render/Shaders/Starfield/StarfieldStars.metal`: add Sun full-screen fragment shader.
- `Tests/ImmersiveMapTests/EarthSceneSettingsTests.swift`: defaults test.
- `Tests/ImmersiveMapTests/EarthSceneUniformTests.swift`: clamping and ABI tests.
- `Tests/ImmersiveMapTests/ImmersiveMapSettingsApplicationPlannerTests.swift`: live-apply test for `scene.earth.sun`.

---

### Task 1: Add Sun Settings and Earth Scene ABI

**Files:**

- Modify: `ImmersiveMap/Configuration/ImmersiveMapSettings.swift`
- Modify: `ImmersiveMap/EarthScene/EarthSceneUniform.swift`
- Modify: `ImmersiveMap/Render/Shaders/Shared/RenderUniforms.h`
- Modify: `Tests/ImmersiveMapTests/EarthSceneSettingsTests.swift`
- Modify: `Tests/ImmersiveMapTests/EarthSceneUniformTests.swift`
- Modify: `Tests/ImmersiveMapTests/ImmersiveMapSettingsApplicationPlannerTests.swift`

- [ ] **Step 1: Write failing settings tests**

Add to `EarthSceneSettingsTests`:

```swift
func testDefaultSunSettingsAreEnabledForEarthScene() {
    let sun = ImmersiveMapSettings.default.scene.earth.sun

    XCTAssertTrue(sun.isEnabled)
    XCTAssertEqual(sun.diskAngularSize, 0.075, accuracy: 0.0001)
    XCTAssertEqual(sun.diskIntensity, 1.0, accuracy: 0.0001)
    XCTAssertEqual(sun.glowIntensity, 0.75, accuracy: 0.0001)
    XCTAssertEqual(sun.edgeGlareIntensity, 0.55, accuracy: 0.0001)
    XCTAssertEqual(sun.limbHaloIntensity, 0.35, accuracy: 0.0001)
    XCTAssertEqual(sun.limbHaloWidth, 0.10, accuracy: 0.0001)
}
```

- [ ] **Step 2: Write failing uniform tests**

In `EarthSceneUniformTests`, extend `testDisabledUniformDisablesEarthSceneAndNightLights`:

```swift
XCTAssertEqual(uniform.sunVisualEnabled, 0)
```

Add:

```swift
func testSunVisualValuesAreClampedAndResolvedSafely() {
    let settings = ImmersiveMapSettings.EarthSceneSettings(
        sun: .init(isEnabled: true,
                   diskAngularSize: -2.0,
                   diskIntensity: 1.4,
                   glowIntensity: .infinity,
                   edgeGlareIntensity: -0.25,
                   limbHaloIntensity: 2.0,
                   limbHaloWidth: 0.0)
    )

    let uniform = EarthSceneUniform(settings: settings, now: .distantPast)

    XCTAssertEqual(uniform.sunVisualEnabled, 1)
    XCTAssertEqual(uniform.sunDiskAngularSize, EarthSceneUniform.minimumFadeWidth, accuracy: 0.0001)
    XCTAssertEqual(uniform.sunDiskIntensity, 1.0, accuracy: 0.0001)
    XCTAssertEqual(uniform.sunGlowIntensity, 0.0, accuracy: 0.0001)
    XCTAssertEqual(uniform.sunEdgeGlareIntensity, 0.0, accuracy: 0.0001)
    XCTAssertEqual(uniform.sunLimbHaloIntensity, 1.0, accuracy: 0.0001)
    XCTAssertEqual(uniform.sunLimbHaloWidth, EarthSceneUniform.minimumFadeWidth, accuracy: 0.0001)
}
```

Update ABI expectations to the new layout:

```swift
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.stride, 80)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.alignment, 16)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunDirection), 0)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.isEnabled), 16)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.daySideMinimumBrightness), 20)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightSideBrightness), 24)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.terminatorFadeWidth), 28)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightLightsIntensity), 32)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightLightsTerminatorFadeWidth), 36)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.nightLightsEnabled), 40)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunVisualEnabled), 44)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunDiskAngularSize), 48)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunDiskIntensity), 52)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunGlowIntensity), 56)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunEdgeGlareIntensity), 60)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunLimbHaloIntensity), 64)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \.sunLimbHaloWidth), 68)
XCTAssertEqual(MemoryLayout<EarthSceneUniform>.offset(of: \._padding0), 72)
```

- [ ] **Step 3: Write failing planner test**

Add to `ImmersiveMapSettingsApplicationPlannerTests`:

```swift
func testEarthSceneSunVisualChangeIsLiveApplied() {
    let oldSettings = ImmersiveMapSettings.default
    var newSettings = oldSettings
    newSettings.scene.earth.sun.edgeGlareIntensity = 0.42

    let plan = ImmersiveMapSettingsApplicationPlanner.makePlan(from: oldSettings, to: newSettings)

    XCTAssertEqual(plan.changedDomains, [.scene])
    XCTAssertEqual(plan.actions, [.liveApply])
    XCTAssertFalse(plan.requiresRendererRecreation)
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run:

```bash
swift test --filter EarthSceneSettingsTests
swift test --filter EarthSceneUniformTests
swift test --filter ImmersiveMapSettingsApplicationPlannerTests
```

Expected: compile failures because `sun`, `sunVisualEnabled`, and related fields do not exist yet.

- [ ] **Step 5: Implement settings**

Inside `ImmersiveMapSettings.EarthSceneSettings`, add:

```swift
public struct SunSettings: Equatable {
    public var isEnabled: Bool
    /// Artistic normalized angular size for the visible disk. Must be positive.
    public var diskAngularSize: Float
    /// Disk contribution multiplier. Expected range: `0...1`.
    public var diskIntensity: Float
    /// Outer glow contribution multiplier. Expected range: `0...1`.
    public var glowIntensity: Float
    /// Screen-edge glare contribution multiplier. Expected range: `0...1`.
    public var edgeGlareIntensity: Float
    /// Limb halo contribution multiplier. Expected range: `0...1`.
    public var limbHaloIntensity: Float
    /// Positive normalized screen-space width for the limb halo.
    public var limbHaloWidth: Float

    public init(isEnabled: Bool = true,
                diskAngularSize: Float = 0.075,
                diskIntensity: Float = 1.0,
                glowIntensity: Float = 0.75,
                edgeGlareIntensity: Float = 0.55,
                limbHaloIntensity: Float = 0.35,
                limbHaloWidth: Float = 0.10) {
        self.isEnabled = isEnabled
        self.diskAngularSize = diskAngularSize
        self.diskIntensity = diskIntensity
        self.glowIntensity = glowIntensity
        self.edgeGlareIntensity = edgeGlareIntensity
        self.limbHaloIntensity = limbHaloIntensity
        self.limbHaloWidth = limbHaloWidth
    }
}
```

Add property and initializer parameter:

```swift
public var sun: SunSettings

public init(isEnabled: Bool = true,
            timeMode: EarthSceneTimeMode = .realtime,
            daySideMinimumBrightness: Float = 0.82,
            nightSideBrightness: Float = 0.18,
            terminatorFadeWidth: Float = 0.12,
            nightLights: NightLightsSettings = NightLightsSettings(),
            sun: SunSettings = SunSettings()) {
    self.isEnabled = isEnabled
    self.timeMode = timeMode
    self.daySideMinimumBrightness = daySideMinimumBrightness
    self.nightSideBrightness = nightSideBrightness
    self.terminatorFadeWidth = terminatorFadeWidth
    self.nightLights = nightLights
    self.sun = sun
}
```

- [ ] **Step 6: Implement Swift uniform fields**

Change `EarthSceneUniform` fields after `nightLightsEnabled`:

```swift
var nightLightsEnabled: UInt32
var sunVisualEnabled: UInt32
var sunDiskAngularSize: Float
var sunDiskIntensity: Float
var sunGlowIntensity: Float
var sunEdgeGlareIntensity: Float
var sunLimbHaloIntensity: Float
var sunLimbHaloWidth: Float
var _padding0: SIMD2<UInt32>
```

In `.disabled`, set Sun values to zero except positive widths:

```swift
sunVisualEnabled: 0,
sunDiskAngularSize: minimumFadeWidth,
sunDiskIntensity: 0,
sunGlowIntensity: 0,
sunEdgeGlareIntensity: 0,
sunLimbHaloIntensity: 0,
sunLimbHaloWidth: minimumFadeWidth,
_padding0: SIMD2<UInt32>(repeating: 0)
```

In `init(settings:now:)`, resolve:

```swift
let sun = settings.sun
```

Pass:

```swift
sunVisualEnabled: sun.isEnabled ? 1 : 0,
sunDiskAngularSize: Self.resolvedFadeWidth(sun.diskAngularSize),
sunDiskIntensity: Self.clampedUnit(sun.diskIntensity),
sunGlowIntensity: Self.clampedUnit(sun.glowIntensity),
sunEdgeGlareIntensity: Self.clampedUnit(sun.edgeGlareIntensity),
sunLimbHaloIntensity: Self.clampedUnit(sun.limbHaloIntensity),
sunLimbHaloWidth: Self.resolvedFadeWidth(sun.limbHaloWidth),
_padding0: SIMD2<UInt32>(repeating: 0)
```

Update the private initializer signature with the same fields.

- [ ] **Step 7: Implement Metal ABI mirror**

Update `struct EarthScene` in `RenderUniforms.h`:

```metal
struct EarthScene {
    float3 sunDirection;
    uint isEnabled;
    float daySideMinimumBrightness;
    float nightSideBrightness;
    float terminatorFadeWidth;
    float nightLightsIntensity;
    float nightLightsTerminatorFadeWidth;
    uint nightLightsEnabled;
    uint sunVisualEnabled;
    float sunDiskAngularSize;
    float sunDiskIntensity;
    float sunGlowIntensity;
    float sunEdgeGlareIntensity;
    float sunLimbHaloIntensity;
    float sunLimbHaloWidth;
    uint2 _padding0;
};
```

- [ ] **Step 8: Run focused tests and commit**

Run:

```bash
swift test --filter EarthSceneSettingsTests
swift test --filter EarthSceneUniformTests
swift test --filter ImmersiveMapSettingsApplicationPlannerTests
```

Expected: all three filtered suites pass.

Commit:

```bash
git add ImmersiveMap/Configuration/ImmersiveMapSettings.swift ImmersiveMap/EarthScene/EarthSceneUniform.swift ImmersiveMap/Render/Shaders/Shared/RenderUniforms.h Tests/ImmersiveMapTests/EarthSceneSettingsTests.swift Tests/ImmersiveMapTests/EarthSceneUniformTests.swift Tests/ImmersiveMapTests/ImmersiveMapSettingsApplicationPlannerTests.swift
git commit -m "feat: add sun visual settings"
```

---

### Task 2: Add Sun Visual Projection Helper

**Files:**

- Create: `ImmersiveMap/EarthScene/EarthSceneSunVisualState.swift`
- Create: `Tests/ImmersiveMapTests/EarthSceneSunVisualStateTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/ImmersiveMapTests/EarthSceneSunVisualStateTests.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import simd
import XCTest

final class EarthSceneSunVisualStateTests: XCTestCase {
    func testDisabledEarthSceneReturnsDisabledSunState() {
        let state = EarthSceneSunVisualState.make(earthScene: .disabled,
                                                  globe: GlobeUniform(panX: 0, panY: 0, radius: 1, transition: 0),
                                                  cameraMatrix: matrix_identity_float4x4,
                                                  drawSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(state.isEnabled, 0)
        XCTAssertEqual(state.diskAlpha, 0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, 0, accuracy: 0.0001)
    }

    func testVisibleSunOutsideGlobeSilhouetteDrawsDiskAndGlare() {
        var earth = EarthSceneUniform(settings: ImmersiveMapSettings.default.scene.earth, now: .distantPast)
        earth.sunDirection = SIMD3<Float>(1, 0, 0)

        let state = EarthSceneSunVisualState.make(earthScene: earth,
                                                  globe: GlobeUniform(panX: 0, panY: 0, radius: 1, transition: 0),
                                                  cameraMatrix: matrix_identity_float4x4,
                                                  drawSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(state.isEnabled, 1)
        XCTAssertGreaterThan(state.diskAlpha, 0.9)
        XCTAssertGreaterThan(state.edgeGlareAlpha, 0.0)
        XCTAssertEqual(state.limbHaloAlpha, 0, accuracy: 0.0001)
    }

    func testSunInsideGlobeSilhouetteNearLimbSuppressesDiskAndKeepsHalo() {
        var earth = EarthSceneUniform(settings: ImmersiveMapSettings.default.scene.earth, now: .distantPast)
        earth.sunDirection = normalize(SIMD3<Float>(0.48, 0, 0.88))

        let state = EarthSceneSunVisualState.make(earthScene: earth,
                                                  globe: GlobeUniform(panX: 0, panY: 0, radius: 1, transition: 0),
                                                  cameraMatrix: matrix_identity_float4x4,
                                                  drawSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(state.diskAlpha, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(state.limbHaloAlpha, 0.1)
    }

    func testSunBehindCameraSuppressesAllVisibleContributions() {
        var earth = EarthSceneUniform(settings: ImmersiveMapSettings.default.scene.earth, now: .distantPast)
        earth.sunDirection = SIMD3<Float>(0, 0, -1)

        let state = EarthSceneSunVisualState.make(earthScene: earth,
                                                  globe: GlobeUniform(panX: 0, panY: 0, radius: 1, transition: 0),
                                                  cameraMatrix: matrix_identity_float4x4,
                                                  drawSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(state.diskAlpha, 0, accuracy: 0.0001)
        XCTAssertEqual(state.edgeGlareAlpha, 0, accuracy: 0.0001)
        XCTAssertEqual(state.limbHaloAlpha, 0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter EarthSceneSunVisualStateTests
```

Expected: compile failure because `EarthSceneSunVisualState` does not exist.

- [ ] **Step 3: Implement visual state helper**

Create `ImmersiveMap/EarthScene/EarthSceneSunVisualState.swift`:

```swift
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import simd

struct EarthSceneSunVisualState {
    var screenCenter: SIMD2<Float>
    var clampedScreenCenter: SIMD2<Float>
    var globeScreenCenter: SIMD2<Float>
    var globeScreenRadius: Float
    var diskAlpha: Float
    var edgeGlareAlpha: Float
    var limbHaloAlpha: Float
    var isEnabled: UInt32
    var padding: UInt32 = 0

    static let disabled = EarthSceneSunVisualState(screenCenter: SIMD2<Float>(0.5, 0.5),
                                                   clampedScreenCenter: SIMD2<Float>(0.5, 0.5),
                                                   globeScreenCenter: SIMD2<Float>(0.5, 0.5),
                                                   globeScreenRadius: 0,
                                                   diskAlpha: 0,
                                                   edgeGlareAlpha: 0,
                                                   limbHaloAlpha: 0,
                                                   isEnabled: 0)

    static func make(earthScene: EarthSceneUniform,
                     globe: GlobeUniform,
                     cameraMatrix: matrix_float4x4,
                     drawSize: CGSize) -> EarthSceneSunVisualState {
        guard earthScene.isEnabled != 0,
              earthScene.sunVisualEnabled != 0,
              drawSize.width > 0,
              drawSize.height > 0 else {
            return .disabled
        }

        let direction = simd_normalize(earthScene.sunDirection)
        guard direction.z >= -0.0001 else {
            return .disabled
        }

        let screenCenter = SIMD2<Float>(0.5 + direction.x * 0.5,
                                        0.5 - direction.y * 0.5)
        let clamped = simd_clamp(screenCenter,
                                 SIMD2<Float>(repeating: 0),
                                 SIMD2<Float>(repeating: 1))
        let globeCenter = SIMD2<Float>(0.5, 0.5)
        let globeRadius = max(0.001, min(Float(drawSize.width), Float(drawSize.height)) / max(Float(drawSize.width), Float(drawSize.height)) * 0.25)
        let distanceFromGlobeCenter = simd_length(screenCenter - globeCenter)
        let insideGlobeSilhouette = distanceFromGlobeCenter < globeRadius
        let limbDistance = abs(distanceFromGlobeCenter - globeRadius)
        let limbFactor = max(0, 1 - limbDistance / max(earthScene.sunLimbHaloWidth, EarthSceneUniform.minimumFadeWidth))
        let offscreenDistance = simd_length(screenCenter - clamped)

        return EarthSceneSunVisualState(
            screenCenter: screenCenter,
            clampedScreenCenter: clamped,
            globeScreenCenter: globeCenter,
            globeScreenRadius: globeRadius,
            diskAlpha: insideGlobeSilhouette ? 0 : 1,
            edgeGlareAlpha: insideGlobeSilhouette ? 0 : max(0.25, min(1, 1 - offscreenDistance)),
            limbHaloAlpha: insideGlobeSilhouette ? limbFactor : 0,
            isEnabled: 1
        )
    }
}
```

This helper intentionally starts with a simple deterministic screen model. Later implementation review may replace the approximate globe center/radius with exact projection from `cameraMatrix`; tests should then be updated to assert the same visible behavior.

- [ ] **Step 4: Run focused tests and commit**

Run:

```bash
swift test --filter EarthSceneSunVisualStateTests
```

Expected: suite passes.

Commit:

```bash
git add ImmersiveMap/EarthScene/EarthSceneSunVisualState.swift Tests/ImmersiveMapTests/EarthSceneSunVisualStateTests.swift
git commit -m "feat: classify sun visual state"
```

---

### Task 3: Add Metal Sun Pass

**Files:**

- Modify: `ImmersiveMap/Render/Starfield/StarfieldPipeline.swift`
- Modify: `ImmersiveMap/Render/Shaders/Starfield/StarfieldStars.metal`

- [ ] **Step 1: Add shader structs and functions**

In `StarfieldStars.metal`, add near existing structs:

```metal
struct SunVisualState {
    float2 screenCenter;
    float2 clampedScreenCenter;
    float2 globeScreenCenter;
    float globeScreenRadius;
    float diskAlpha;
    float edgeGlareAlpha;
    float limbHaloAlpha;
    uint isEnabled;
    uint padding;
};
```

Add full-screen Sun shaders after `starfieldBackgroundFragmentShader`:

```metal
vertex BackgroundVertexOut sunVertexShader(uint vertexID [[vertex_id]]) {
    return starfieldBackgroundVertexShader(vertexID);
}

fragment float4 sunFragmentShader(BackgroundVertexOut in [[stage_in]],
                                  constant EarthScene& earth [[buffer(0)]],
                                  constant SunVisualState& sun [[buffer(1)]]) {
    if (earth.isEnabled == 0 || earth.sunVisualEnabled == 0 || sun.isEnabled == 0) {
        return float4(0.0);
    }

    float2 uv = in.uv;
    float diskDistance = distance(uv, sun.screenCenter);
    float diskRadius = max(earth.sunDiskAngularSize, 0.001);
    float core = exp(-pow(diskDistance / diskRadius, 2.0) * 2.6) * sun.diskAlpha;
    float glow = exp(-pow(diskDistance / (diskRadius * 3.5), 2.0)) * sun.diskAlpha;

    float edgeDistance = distance(uv, sun.clampedScreenCenter);
    float edgeGlare = exp(-edgeDistance * 8.0) * sun.edgeGlareAlpha;

    float globeDistance = distance(uv, sun.globeScreenCenter);
    float limbDistance = abs(globeDistance - sun.globeScreenRadius);
    float limb = exp(-pow(limbDistance / max(earth.sunLimbHaloWidth, 0.001), 2.0) * 6.0) * sun.limbHaloAlpha;

    float3 warmCore = float3(1.0, 0.94, 0.72);
    float3 orangeGlow = float3(1.0, 0.45, 0.12);
    float3 color = warmCore * core * earth.sunDiskIntensity
        + orangeGlow * glow * earth.sunGlowIntensity
        + orangeGlow * edgeGlare * earth.sunEdgeGlareIntensity
        + warmCore * limb * earth.sunLimbHaloIntensity;
    float alpha = saturate(core + glow * 0.7 + edgeGlare * 0.45 + limb * 0.55);
    return float4(color, alpha);
}
```

- [ ] **Step 2: Add pipeline state**

In `StarfieldPipeline`, add:

```swift
let sunPipelineState: MTLRenderPipelineState
```

In `init`, create functions:

```swift
let sunVertexFunction = library.makeFunction(name: "sunVertexShader")
let sunFragmentFunction = library.makeFunction(name: "sunFragmentShader")
```

Create descriptor after `pipelineDescriptor`:

```swift
let sunDescriptor = MTLRenderPipelineDescriptor()
sunDescriptor.vertexFunction = sunVertexFunction
sunDescriptor.fragmentFunction = sunFragmentFunction
sunDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
sunDescriptor.depthAttachmentPixelFormat = .depth32Float
sunDescriptor.colorAttachments[0].isBlendingEnabled = true
sunDescriptor.colorAttachments[0].rgbBlendOperation = .add
sunDescriptor.colorAttachments[0].alphaBlendOperation = .add
sunDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
sunDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
sunDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
sunDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
```

In the `do` block:

```swift
sunPipelineState = try metalDevice.makeRenderPipelineState(descriptor: sunDescriptor)
```

Add selector:

```swift
func selectSunPipeline(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setRenderPipelineState(sunPipelineState)
}
```

- [ ] **Step 3: Compile shaders**

Run:

```bash
swift test --filter EarthSceneUniformTests
```

Expected: build succeeds and the filtered suite passes.

- [ ] **Step 4: Commit**

```bash
git add ImmersiveMap/Render/Starfield/StarfieldPipeline.swift ImmersiveMap/Render/Shaders/Starfield/StarfieldStars.metal
git commit -m "feat: add sun starfield pipeline"
```

---

### Task 4: Integrate Sun Pass Into Starfield Rendering

**Files:**

- Modify: `ImmersiveMap/Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift`
- Modify: `ImmersiveMap/Render/Starfield/StarfieldRenderer.swift`

- [ ] **Step 1: Update renderer method signature**

Change `StarfieldRenderer.draw` signature:

```swift
func draw(renderEncoder: MTLRenderCommandEncoder,
          globe: GlobeUniform,
          earthScene: EarthSceneUniform,
          cameraView: matrix_float4x4,
          cameraEye: SIMD3<Float>,
          drawSize: CGSize,
          nowTime: Float)
```

- [ ] **Step 2: Pass Earth scene from subsystem**

In `StarfieldRenderSubsystem.encode`, update the call:

```swift
starfieldRenderer.draw(renderEncoder: encoder,
                       globe: frameContext.globeRenderUniform,
                       earthScene: frameContext.earthSceneUniform,
                       cameraView: frameContext.cameraMatrices.view,
                       cameraEye: frameContext.cameraEye,
                       drawSize: frameContext.drawSize,
                       nowTime: Float(frameContext.time))
```

- [ ] **Step 3: Encode Sun pass after stars**

In `StarfieldRenderer.draw`, after the existing stars `drawPrimitives`, add:

```swift
var earthSceneData = earthScene
var sunState = EarthSceneSunVisualState.make(earthScene: earthScene,
                                             globe: globe,
                                             cameraMatrix: starCameraMatrix,
                                             drawSize: drawSize)

pipeline.selectSunPipeline(renderEncoder: renderEncoder)
renderEncoder.setFragmentBytes(&earthSceneData,
                               length: MemoryLayout<EarthSceneUniform>.stride,
                               index: 0)
renderEncoder.setFragmentBytes(&sunState,
                               length: MemoryLayout<EarthSceneSunVisualState>.stride,
                               index: 1)
renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
```

- [ ] **Step 4: Run integration tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add ImmersiveMap/Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift ImmersiveMap/Render/Starfield/StarfieldRenderer.swift
git commit -m "feat: render astronomical sun glow"
```

---

### Task 5: Build and Visual Validation

**Files:**

- No source edits expected unless validation reveals a defect.

- [ ] **Step 1: Run package tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Build Mac Catalyst host**

Run:

```bash
xcodebuild -workspace ImmersiveMap.xcworkspace -scheme ImmersiveMapMac -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/ImmersiveMapSunObjectMacDerivedData build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Build/run iOS simulator host**

Use XcodeBuildMCP:

1. Call `session_show_defaults`.
2. If defaults are unset, set workspace `/Users/artembobkin/Desktop/ImmersiveMap/ImmersiveMap.xcworkspace`, scheme `ImmersiveMapIOS`, and an available iPhone simulator.
3. Call `build_run_sim`.

Expected: app builds, installs, and launches without errors.

- [ ] **Step 4: Manual visual checks**

Check these states in the host app:

- Globe visible with starfield background.
- Sun disk/glow appears in the astronomical light direction when the Sun is on-screen.
- Moving/rotating the globe keeps the Sun aligned with the day/night terminator.
- When the Sun is hidden by Earth, the disk does not draw over the globe.
- Limb halo remains visible near the lit edge.
- Edge glare appears from the correct side when the Sun is just off-screen.
- Turning `settings.scene.earth.isEnabled = false` removes Sun disk, edge glare, and halo.
- Debug overlay and labels remain readable over the Sun pass.

- [ ] **Step 5: Final checks**

Run:

```bash
git diff --check main...HEAD
git status --short --ignored
```

Expected: no whitespace errors; status contains only intended source/test changes and ignored build artifacts.

Commit any validation-driven fixes with precise messages such as:

```bash
git commit -m "fix: tune sun occlusion glare"
```

Do not commit `.build/`, DerivedData, `.swiftpm/`, `.superpowers/`, xcuserdata, screenshots, or local secrets.

---

## Self-Review

Spec coverage:

- Astronomical anchor: Tasks 1 and 4 consume the existing `EarthSceneUniform.sunDirection`.
- Visible disk and glow: Task 3 adds the full-screen Sun shader.
- Edge glare: Task 3 computes edge glare from `clampedScreenCenter`.
- Cinematic limb halo: Tasks 2 and 3 classify and draw halo when the disk is suppressed.
- Spherical-only integration: Task 4 integrates through `StarfieldRenderSubsystem`, which already guards `.spherical`.
- Live settings: Task 1 adds planner coverage for `scene.earth.sun`.
- Tests and validation: Tasks 1, 2, and 5 cover unit, build, and visual checks.

Completeness scan: every task includes concrete files, commands, expected results, and implementation snippets for this MVP.

Type consistency: `EarthSceneSettings.SunSettings`, `EarthSceneUniform.sunVisualEnabled`, and `EarthSceneSunVisualState` are introduced before later tasks consume them.
