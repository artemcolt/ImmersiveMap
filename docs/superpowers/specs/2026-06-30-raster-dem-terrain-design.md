# Raster DEM Terrain Design

## Goal

Add a first working terrain-rendering path that can draw 3D mountains from Re:Earth Terrain raster DEM tiles, expose it through SwiftUI settings, and make it switchable from the existing debug panel.

## Scope

This design covers a production-shaped MVP. The first implementation renders terrain from raster DEM height tiles in both flat and globe presentation modes.

Included:

- Public SwiftUI API for selecting a terrain source and enabling/disabling terrain rendering.
- Re:Earth Terrain raster DEM source support.
- Mapbox Terrain-RGB decoding.
- Runtime terrain toggle in the existing debug panel Controls tab.
- A separate terrain loading/rendering path that does not replace the existing vector tile pipeline.
- A visible result in the local `ImmersiveMapMacDevelop` host app when the new API is applied.

Excluded from the first implementation:

- Cesium `quantized-mesh-1.0`.
- Terrain watermask rendering.
- Persistent terrain disk cache.
- Full cross-LOD seam stitching.
- Physics/collision queries against terrain.
- README changes.
- Committing `ImmersiveMapMacDevelop`, because it is ignored and currently contains a local Mapbox token.

## Source Data

The first source is Re:Earth Terrain raster DEM:

- Mapbox Terrain-RGB elevation tiles: `https://terrain.reearth.land/mapbox/elevation/{z}/{x}/{y}.png`
- Mapbox Terrain-RGB ellipsoid TileJSON: `https://terrain.reearth.land/mapbox/ellipsoid/tilejson.json`
- TileJSON advertises WebMercator XYZ, `minzoom: 0`, `maxzoom: 14`, and WebP templates under `/mapterhorn-egm08/mapbox/{datum}/{z}/{x}/{y}.webp`.

The terrain API should support both direct template construction and future TileJSON-driven templates. The MVP may use deterministic Re:Earth URL construction so renderer work is not blocked on a TileJSON client.

Vertical datum options:

- `elevation`: orthometric height, meters above mean sea level. This is the default for visually recognizable mountains.
- `ellipsoid`: WGS84 ellipsoid height. This is useful for globe alignment and future GNSS/3D city-model workflows.
- `geoid`: not rendered as terrain in the MVP, but the type can exist in the source model for future diagnostics.

## Public API

Add a terrain settings domain to `ImmersiveMapSettings`:

```swift
public struct TerrainSettings: Equatable {
    public var isEnabled: Bool
    public var source: ImmersiveMapTerrainSource?
    public var exaggeration: Float
    public var maximumZoomLevel: Int
    public var meshResolution: Int
}
```

Defaults:

- `isEnabled = false`
- `source = nil`
- `exaggeration = 1.0`
- `maximumZoomLevel = 14`
- `meshResolution = 65`

Add public source model:

```swift
public struct ImmersiveMapTerrainSource: Equatable {
    public enum Encoding: Equatable {
        case mapboxTerrainRGB
        case terrarium
    }

    public enum Datum: Equatable {
        case elevation
        case ellipsoid
        case geoid
    }

    public var id: String
    public var baseURL: URL
    public var encoding: Encoding
    public var datum: Datum
    public var maximumZoomLevel: Int

    public static func reEarth(
        baseURL: URL = URL(string: "https://terrain.reearth.land")!,
        encoding: Encoding = .mapboxTerrainRGB,
        datum: Datum = .elevation,
        maximumZoomLevel: Int = 14
    ) -> ImmersiveMapTerrainSource
}
```

Add settings modifiers:

```swift
public func terrainSettings(_ terrain: ImmersiveMapSettings.TerrainSettings) -> ImmersiveMapSettings

public func terrainSource(_ source: ImmersiveMapTerrainSource?) -> ImmersiveMapSettings

public func terrainRendering(
    isEnabled: Bool = true,
    exaggeration: Float? = nil,
    maximumZoomLevel: Int? = nil,
    meshResolution: Int? = nil
) -> ImmersiveMapSettings
```

Add matching `ImmersiveMapView` modifiers:

```swift
public func terrainSettings(_ terrain: ImmersiveMapSettings.TerrainSettings) -> ImmersiveMapView

public func terrainSource(_ source: ImmersiveMapTerrainSource?) -> ImmersiveMapView

public func terrainRendering(
    isEnabled: Bool = true,
    exaggeration: Float? = nil,
    maximumZoomLevel: Int? = nil,
    meshResolution: Int? = nil
) -> ImmersiveMapView
```

Example use:

```swift
ImmersiveMapView()
    .terrainSource(.reEarth(datum: .elevation))
    .terrainRendering(isEnabled: true, exaggeration: 1.5)
    .debugPanel()
```

## Debug Panel

Extend `DebugOverlayControlSnapshot` and `DebugOverlayControlState` with `terrainEnabled`.

Add a `Terrain` switch to the Controls tab in `DebugOverlayHUDView`. It should:

- Reflect the current runtime terrain toggle.
- Call `onTerrainEnabledChanged`.
- Request a frame after the state changes.
- Not mutate `ImmersiveMapSettings.terrain.source`.

Effective terrain rendering is enabled only when:

- `settings.terrain.isEnabled == true`
- `settings.terrain.source != nil`
- `debugOverlayControls.snapshot().terrainEnabled == true`

The debug switch is a runtime visibility control. The SwiftUI API remains the source of truth for whether terrain exists and which remote source to use.

## Rendering Architecture

Add a separate terrain subsystem rather than routing DEM bytes through the MVT parser.

New responsibilities:

- `TerrainTileURLProvider`: builds Re:Earth tile URLs from `Tile` and `ImmersiveMapTerrainSource`.
- `TerrainRGBDecoder`: decodes `CGImage` pixels into meter heights.
- `TerrainTileLoader`: fetches DEM images asynchronously and returns decoded height grids.
- `TerrainMeshBuilder`: converts height grids into CPU vertices/indices.
- `TerrainTileStore`: owns loaded/prepared terrain tiles and evicts stale entries.
- `TerrainRenderSubsystem`: schedules visible terrain tiles and renders them.
- `TerrainPipeline`: Metal pipeline and buffers for terrain geometry.

The first implementation can share the existing visible tile selection where possible:

- Flat mode uses the same WebMercator tile coordinates as vector tiles.
- Globe mode also samples WebMercator raster DEM tiles, matching the current globe texture path.
- Terrain tile zoom is clamped to `settings.terrain.maximumZoomLevel`.

## Mesh Construction

For each terrain tile:

- Build a regular grid of `meshResolution x meshResolution` vertices.
- Sample height from the decoded DEM using nearest or bilinear sampling.
- Generate triangle indices row by row.
- Compute normals from neighboring heights for basic lighting.

Flat position:

- `x/y` match the current flat tile local coordinates.
- `z = heightMeters * exaggeration * flatHeightScale`.

Globe position:

- Convert each grid sample to latitude/longitude using the tile's WebMercator bounds.
- Compute the current sphere position as the globe shader does.
- Move along the Earth normal by `heightMeters * exaggeration * globeHeightScale`.

The scale constants should be chosen conservatively so mountains are visible without exploding the existing camera scale. They should be settings-adjacent internals, not public API in the first version.

## Render Ordering

Terrain should draw as world surface geometry:

- In flat mode, draw before building extrusions and labels.
- In globe mode, draw instead of or immediately before the smooth globe surface.

The MVP should avoid double-opaque terrain/globe z-fighting. If terrain is enabled and loaded for a visible globe tile, the terrain pass should be allowed to cover the smooth globe surface. If no terrain tile is loaded, the smooth globe remains the fallback.

## Error Handling

Terrain failures must not break the map:

- Network failure leaves the smooth map/globe visible.
- Image decode failure drops that terrain tile and records debug diagnostics.
- Missing source disables terrain rendering.
- Unsupported source encoding returns no tile and records a debug reason.

The MVP can keep terrain diagnostics internal or add a short line to existing debug diagnostics if that is straightforward.

## Testing Strategy

Tests should be written before implementation.

Required tests:

- Settings defaults keep terrain disabled with no source.
- Settings and `ImmersiveMapView` terrain modifiers store source, enabled state, exaggeration, max zoom, and mesh resolution.
- Re:Earth URL provider builds `mapbox/elevation/{z}/{x}/{y}.png` and `mapbox/ellipsoid/{z}/{x}/{y}.png`.
- Terrain-RGB decoder converts known RGB triplets into expected meter heights.
- Debug HUD terrain switch invokes its callback and reflects state.
- Runtime effective terrain availability is false without source, false when settings disable terrain, false when debug control disables terrain, and true when all three inputs are enabled.

Manual validation:

- Run `ImmersiveMapMacDevelop` with `.terrainSource(.reEarth(datum: .elevation))` and `.terrainRendering(isEnabled: true, exaggeration: 1.5)`.
- Use the debug panel Controls tab to toggle `Terrain`.
- Verify mountains appear/disappear and the app remains responsive.

## Open Decisions Resolved

- Use raster DEM first, not Cesium quantized mesh.
- Default datum for visual mountains is `elevation`.
- Terrain source is public SwiftUI API; debug panel controls only runtime visibility.
- `ImmersiveMapMacDevelop` may be used for local verification, but changes there should not be committed while it remains ignored and token-bearing.
