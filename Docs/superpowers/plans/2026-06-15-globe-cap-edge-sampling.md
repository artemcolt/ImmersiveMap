# Globe Cap Edge Sampling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make polar caps derive their color from the actual rendered globe tile atlas edge instead of static base colors.

**Architecture:** Keep cap geometry and the existing cap render pass. Draw caps per globe atlas tile mapping, bind that mapping's atlas page texture, and have the cap fragment shader sample the matching north/south WebMercator edge color by longitude. Keep the current static palette as a fallback when no atlas mapping is available.

**Tech Stack:** Swift Package, XCTest, Metal, Metal Shading Language.

---

### Task 1: Add Testable Edge Sample Math

**Files:**
- Create: `ImmersiveMap/Render/Globe/GlobeCapEdgeSampler.swift`
- Test: `Tests/ImmersiveMapTests/GlobeCapEdgeSamplerTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that call `GlobeCapEdgeSampler.atlasSampleUV(latitude:longitude:tileData:)` for north and south pole-edge samples and assert that north samples the top atlas texel row while south samples the bottom atlas texel row.

- [ ] **Step 2: Run failing tests**

Run: `swift test --filter GlobeCapEdgeSamplerTests`

Expected: FAIL because `GlobeCapEdgeSampler` is not defined.

- [ ] **Step 3: Implement minimal helper**

Add a small internal Swift helper that mirrors the atlas UV math used by `Globe.metal`: tile containment by longitude/WebMercator latitude, atlas slot lookup, and half-texel clamping.

- [ ] **Step 4: Run tests**

Run: `swift test --filter GlobeCapEdgeSamplerTests`

Expected: PASS.

### Task 2: Sample Atlas Edge In Cap Shader

**Files:**
- Modify: `ImmersiveMap/Render/Globe/GlobeCapRenderer.swift`
- Modify: `ImmersiveMap/Render/Core/Subsystems/World/GlobeCapRenderSubsystem.swift`
- Modify: `ImmersiveMap/Render/Shaders/Globe/Globe.metal`

- [ ] **Step 1: Extend cap params and varyings**

Add cap fragment inputs for latitude/longitude and cap params for signed edge sample latitude plus a texture-sampling enable flag.

- [ ] **Step 2: Bind atlas page textures per mapping**

Sort `GlobeTilesTexture.Page.tileData` like `GlobeSurfaceDrawer`, bind the active page texture, pass each `TileData` to the cap fragment shader, and draw north/south caps per mapping.

- [ ] **Step 3: Preserve fallback behavior**

When there are no atlas mappings, bind a small fallback texture and render one north/south cap pass using the existing static palette.

- [ ] **Step 4: Build**

Run: `swift test --filter GlobeCapEdgeSamplerTests`

Expected: PASS and shader compilation succeeds as part of package test build.

### Task 3: Final Verification

**Files:**
- Verify changed Swift and Metal files.

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter GlobeCapEdgeSamplerTests`

Expected: PASS.

- [ ] **Step 2: Run package build or tests**

Run: `swift test`

Expected: PASS, or report any unrelated existing failures with exact output.
