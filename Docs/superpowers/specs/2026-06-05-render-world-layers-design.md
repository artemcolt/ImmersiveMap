# Render World Layers Design

## Problem

The render subsystem architecture has clear domains for `Avatars`, `Labels`, `Tiles`, and `Debug`, but the current `Scene` group is too broad. It combines flat map geometry, road geometry, extruded buildings, globe rendering, globe cap rendering, starfield rendering, and shared encoder state setup under one logical `RenderLayer.scene`.

This makes the subsystem graph less explicit than the actual frame composition. Diagnostics also report one coarse `scene` layer duration, hiding the cost of individual world rendering steps.

## Goals

- Replace the broad `RenderLayer.scene` with specific world render layers.
- Preserve the existing Metal pass model: `buildingWinner` remains a separate offscreen pass, and `mainDrawable` remains the primary drawable pass.
- Make world rendering responsibilities as clear as `Avatars` and `Labels`.
- Keep the visual output unchanged for flat and globe modes.
- Improve diagnostics by timing concrete world layers instead of one generic scene layer.

## Non-Goals

- Do not redesign tile loading, placement, parsing, or caching.
- Do not change label, avatar, or debug overlay behavior.
- Do not introduce dynamic world-layer availability based on content counts in this refactor.
- Do not change public API behavior.

## Render Layers

Replace the generic `scene` layer with concrete layers:

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
```

`buildingWinner` remains scheduled only by `RenderPassGraph` as a separate Metal pass for flat mode.

The `mainDrawable` layer order becomes mode-aware:

Flat mode:

```text
flatMapSurface -> buildingExtrusion -> labels -> avatars -> debugOverlay
```

Globe mode:

```text
starfield -> globeSurface -> globeCap -> labels -> avatars -> debugOverlay
```

## Subsystems

Replace the current `Scene` subsystem group with a more specific `World` group:

```text
Render/Core/Subsystems/World/FlatMapSurfaceRenderSubsystem.swift
Render/Core/Subsystems/World/BuildingExtrusionRenderSubsystem.swift
Render/Core/Subsystems/World/BuildingWinnerRenderSubsystem.swift
Render/Core/Subsystems/World/StarfieldRenderSubsystem.swift
Render/Core/Subsystems/World/GlobeSurfaceRenderSubsystem.swift
Render/Core/Subsystems/World/GlobeCapRenderSubsystem.swift
```

Responsibilities:

- `FlatMapSurfaceRenderSubsystem`: draw flat tile geometry, including ground, roads, and bridge overlays.
- `BuildingExtrusionRenderSubsystem`: draw the color pass for flat-mode 3D buildings.
- `BuildingWinnerRenderSubsystem`: draw the offscreen building winner ID pass.
- `StarfieldRenderSubsystem`: draw only the globe-mode space background.
- `GlobeSurfaceRenderSubsystem`: draw the globe mesh using the globe tile texture.
- `GlobeCapRenderSubsystem`: draw the globe cap.

Delete `CommonViewSceneRenderSubsystem`. It currently acts as order-dependent encoder state setup, not as a domain subsystem. Each concrete subsystem should set the depth, cull, and pipeline state it requires before drawing.

## Draw Helpers

`RendererSceneDrawer` should not remain a broad scene drawer. Move or split its methods into narrower render helpers:

```text
Render/Tiles/Drawers/FlatMapSurfaceDrawer.swift
Render/Tiles/Drawers/BuildingExtrusionDrawer.swift
Render/Globe/Drawers/GlobeSurfaceDrawer.swift
Render/Globe/Drawers/GlobeCapDrawer.swift
Render/Starfield/StarfieldRenderer.swift
```

`StarfieldRenderer` can remain as the concrete renderer. The new `StarfieldRenderSubsystem` should own when it is called.

## Planning And Availability

Extend `RenderPassAvailability` so the layer planner can choose world layers by mode:

```swift
struct RenderPassAvailability {
    let renderSurfaceMode: RenderSurfaceMode
    let labelsEnabled: Bool
    let avatarsEnabled: Bool
    let debugOverlayEnabled: Bool
}
```

`RenderLayerPlanner.plan(...)` should build the full ordered layer list:

- For `.flat`, include `flatMapSurface` and `buildingExtrusion`.
- For `.spherical`, include `starfield`, `globeSurface`, and `globeCap`.
- Then append enabled overlay layers: `labels`, `avatars`, `debugOverlay`.

World layers are mode-driven in this refactor. They should not be exposed through individual availability providers until there is a measured reason to skip them based on content or settings.

## Frame Flow

The frame flow remains structurally the same:

1. `RenderFrameEngine` collects input and resolves visibility.
2. `RenderGraph.update(...)` updates all subsystems.
3. `RenderGraph.prepareGPU(...)` prepares GPU resources.
4. `RenderPassGraph.plan(...)` creates Metal pass nodes.
5. `RenderFramePassEncoder` iterates pass nodes and calls `renderGraph.encode(layer:...)`.

The change is that `mainDrawable` contains concrete world layers instead of the single `scene` layer.

## Diagnostics

`FrameDiagnostics.layerDurations` should start reporting concrete world layer timings:

```text
flatMapSurface
buildingExtrusion
starfield
globeSurface
globeCap
labels
avatars
debugOverlay
```

This preserves the existing diagnostics mechanism while making render cost attribution clearer.

## Testing

Add focused unit tests for `RenderLayerPlanner`:

- Flat mode with all overlays enabled.
- Flat mode with overlays disabled.
- Globe mode with all overlays enabled.
- Globe mode with overlays disabled.
- `buildingWinner` is not included in the `mainDrawable` layer plan.

Run the existing package build after implementation.

If host builds are available, build at least the Mac Catalyst host app. Visual verification should cover:

- Flat city view with buildings and overlays.
- Globe view with starfield, globe surface, globe cap, and overlays.

## Risks

The main risk is implicit Metal state order. The current `CommonViewSceneRenderSubsystem` sets `depthDisabledState` before scene drawing, while `RendererSceneDrawer` changes depth and cull state inside broad draw methods. Splitting the draw path must preserve equivalent state setup:

- Flat map surface must select the flat tile pipeline and set required camera/fade uniforms.
- Building extrusion must set cull mode, depth state, winner ID texture, lighting uniforms, and restore the states expected by later overlay layers.
- Starfield must not affect map depth precision.
- Globe surface must set globe depth state and cull mode explicitly.
- Globe cap must set globe cap depth state explicitly.
- Overlay layers must continue to set their own depth state before drawing.

## Migration Strategy

Implement as one behavior-preserving refactor:

1. Introduce concrete `RenderLayer` cases and mode-aware `RenderLayerPlanner`.
2. Update layer guards in existing subsystems.
3. Split flat scene rendering into flat map surface and building extrusion subsystems.
4. Split globe scene rendering into starfield, globe surface, and globe cap subsystems.
5. Move `BuildingWinnerRenderSubsystem` into the new `World` group.
6. Delete `CommonViewSceneRenderSubsystem`.
7. Split or narrow `RendererSceneDrawer` helpers.
8. Add planner tests.
9. Build and visually verify flat and globe modes.

The refactor should not change the order of visible draw operations inside each mode.
