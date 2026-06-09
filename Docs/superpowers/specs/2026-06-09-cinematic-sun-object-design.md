# Cinematic Sun Object Design

## Goal

Add a visible Sun to the globe scene that uses the same astronomical date/time source as `EarthSceneUniform.sunDirection`. The visual target is "Sun + screen glare": a warm glowing disk when the Sun is in view, soft edge glare when it is near or outside the viewport, and a cinematic limb halo when the globe hides the disk.

## Scope

This design covers a first production-ready pass for the Sun object. It does not introduce a general HDR bloom pipeline, clouds, atmosphere scattering, or physically scaled solar angular diameter. Those can be layered later once the Earth scene has a stable visual baseline.

The feature is active only for spherical globe rendering and only when the Earth scene is enabled.

## Visual Behavior

The Sun is anchored to the real astronomical `sunDirection` computed from `EarthSceneSettings.timeMode`. Its visual position must therefore match the day/night terminator and night-lights fade.

When the Sun direction projects into the viewport, the renderer draws a camera-facing emissive disk with a warm core, orange outer falloff, and additive glow. The visual disk uses an artistic angular size instead of the true solar angular size because the real value would be too small at map UI scale.

When the Sun is near or outside a viewport edge, the renderer keeps a soft screen-space glare clamped to that edge. This gives the user a directional cue without requiring the Sun disk to be visible.

When the Sun is geometrically behind the globe, the hard disk must not draw over Earth. Instead, the renderer may draw a controlled rim/limb halo on the lit edge of the globe. This keeps the scene rich while respecting depth enough that the globe still feels solid.

## Architecture

The Sun belongs to the starfield/world-background path, not to globe tile rendering. The implementation should extend `StarfieldRenderSubsystem` and `StarfieldRenderer` because that layer already draws before `globeSurface` and `globeCap` in spherical mode.

`StarfieldRenderSubsystem.encode` should pass `frameContext.earthSceneUniform` into `StarfieldRenderer.draw`. `StarfieldRenderer` should keep the existing background and stars draws, then encode a Sun draw using a new small pipeline or a new mode in `StarfieldPipeline`.

The Sun renderer should use additive blending like stars. It should avoid depth writes. The disk can be drawn as a screen-facing quad or point-expanded quad in clip space after projecting the world-space Sun direction through the starfield camera matrix. The glare can be computed in screen space from the projected/clamped Sun center.

The globe surface shader should remain responsible for terrain day/night shading and night lights. The Sun object should consume the Earth scene state but should not change tile atlas, label, avatar, or debug overlay pipelines.

## Settings

Add a nested `EarthSceneSettings.SunSettings` because the Sun visual is part of the Earth scene, not generic stars.

Initial settings:

- `isEnabled: Bool = true`
- `diskAngularSize: Float = 0.075`
- `diskIntensity: Float = 1.0`
- `glowIntensity: Float = 0.75`
- `edgeGlareIntensity: Float = 0.55`
- `limbHaloIntensity: Float = 0.35`
- `limbHaloWidth: Float = 0.10`

The implementation should clamp shader-facing numeric values so invalid app settings cannot produce NaN, negative sizes, or unstable blending.

Changing these settings should be live-applied like the existing `scene.earth` settings.

## Data Flow

Each frame:

1. `RenderFrameEngine` captures `Date()` and builds `FrameContextServices`.
2. `FrameContext.earthSceneUniform` resolves Earth scene settings into shader-facing values.
3. `StarfieldRenderSubsystem` passes the globe uniform, camera matrices, draw size, time, and Earth scene uniform to `StarfieldRenderer`.
4. The Sun pass projects `earthScene.sunDirection` into the same visual sky basis used by the starfield.
5. The Sun shader draws disk/glow when visible and emits edge/limb glow based on visibility and occlusion classification.

The direction basis must remain consistent with the existing globe shader and `EarthSceneSunCalculator`: `(lat: 0, lon: 0) -> +Z`, `90E -> +X`.

## Occlusion Model

The MVP should use an analytic classification rather than a full depth query:

- Sun projects in front of the camera and outside the globe silhouette: draw disk and glow.
- Sun projects inside the globe silhouette but close to the visible limb: suppress disk, draw limb halo.
- Sun projects inside the globe silhouette and far from the limb: suppress disk and reduce edge glare.
- Sun is behind the camera: suppress disk and edge glare.

This keeps the feature deterministic and testable without adding a readback or depth-dependent post-process.

## Testing

Add focused tests for:

- Sun settings defaults and clamping.
- Settings planner live-apply behavior for `scene.earth.sun`.
- Projection/visibility helper classification for in-front, behind-limb, and hidden Sun directions.
- ABI layout if a new shader uniform struct is introduced.

Renderer validation should include screenshots or simulator/manual checks for:

- Sun visible on the day side.
- Sun behind the globe: no disk over Earth, limb halo remains.
- Sun just outside the viewport: edge glare points toward the off-screen Sun.
- Earth scene disabled: no Sun object or glare.

## Risks

The largest visual risk is over-bright additive glare washing out map labels and debug overlays. Keep the Sun pass before labels/debug overlay and expose conservative defaults.

The largest technical risk is basis drift between the globe shader, starfield rotation, and Earth scene sun direction. Keep the direction conversion isolated and covered by tests.

Polar caps currently have separate globe-cap rendering. Limb halo should be based on the globe sphere, not tile coverage, so it should still look coherent while polar cap lighting is improved separately later.
