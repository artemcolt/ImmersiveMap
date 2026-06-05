# Vector Tile Adaptation Label Decisions Design

## Context

ImmersiveMap currently makes many point/base label decisions inside
`TileMvtParser`: text fallback, provider-specific rank fields, class/type
interpretation, visibility thresholds, collision priority, and label identity.
That works for the current Mapbox-oriented tile schema, but it makes the public
engine fragile when a different vector tile provider uses different layer names,
name fields, feature identifiers, ranks, or class taxonomies.

The new `ImmersiveMap/VectorTileAdaptation` folder is the internal boundary for
provider-specific schema interpretation. It must keep provider adaptation and
label decision logic out of renderer runtime code.

## Goal

Create an internal point/base label decision layer under
`ImmersiveMap/VectorTileAdaptation/Labels` that converts raw vector tile feature
data into provider-neutral label decisions.

The first implementation slice should preserve the existing renderer pipeline:
the new layer may still adapt its output back into `TileMvtParser.TextLabel` so
`TileTextLabelsBuilder`, `BaseLabelCache`, fade state, collision runtime, Metal
buffers, and shaders do not need to change.

## Non-Goals

- Do not change public API in this slice.
- Do not migrate road labels.
- Do not rewrite `BaseLabelCache`, collision resolution, fade animation, or draw
  shaders.
- Do not introduce a full Mapbox Style expression engine.
- Do not make network, auth, or tile URL provider decisions in this folder.

## Proposed Structure

```text
ImmersiveMap/VectorTileAdaptation/
  README.md
  Labels/
    Core/
      VectorTileLabelFeature.swift
      VectorTileLabelDecision.swift
      VectorTileLabelIdentity.swift
      VectorTileLabelPriority.swift
      VectorTileLabelPlacementIntent.swift

    Providers/
      VectorTileLabelProviderProfile.swift
      MapboxVectorTileLabelProviderProfile.swift

    Text/
      VectorTileLabelTextResolver.swift
      VectorTileLabelLanguagePreferences.swift
      VectorTileLabelGlyphCoverage.swift

    Decisions/
      VectorTileLabelDecisionEngine.swift
```

## Data Flow

```text
Raw MVT point feature
  -> VectorTileLabelFeature
  -> VectorTileLabelProviderProfile
  -> VectorTileLabelDecisionEngine
  -> VectorTileLabelDecision
  -> existing TileMvtParser.TextLabel
  -> existing TileTextLabelsBuilder
```

`TileMvtParser` should remain responsible for MVT geometry decoding and for
passing feature data into the adaptation layer. It should no longer own
provider-specific label rules once the slice is complete.

## Core Model

`VectorTileLabelFeature` represents one decoded point feature and its provider
context:

- provider id
- tile coordinate
- layer name
- optional feature id
- local point anchor
- raw MVT properties

`VectorTileLabelDecision` is the provider-neutral answer for a renderable base
label:

- text
- identity
- priority
- placement intent
- text style
- optional POI icon

`VectorTileLabelIdentity` must make deduplication explicit:

- `providerFeature`: for provider feature ids that the active profile considers
  stable enough for cross-tile identity.
- `semantic`: for stable semantic labels built from normalized kind, text, and a
  coarse world bucket.
- `tileLocal`: for fallback labels that should not accidentally deduplicate
  unrelated labels in other tiles.

`VectorTileLabelPriority` separates concerns that are currently folded into one
`sortKey`:

- visibility rank
- collision rank
- deduplication rank
- draw rank

`VectorTileLabelPlacementIntent` describes renderer-facing placement semantics:

- collision padding
- collision shape
- anchor mode
- screen offset
- future placement candidate support

The first slice may only apply collision padding and centered anchor behavior,
but the model should not prevent richer placement later.

## Provider Profile

`VectorTileLabelProviderProfile` is the provider-specific schema adapter. It
answers questions such as:

- Which source layers contain base point labels?
- Which layers should be excluded from base labels?
- Which property fields contain localized names?
- Which rank fields should be considered, and in what order?
- How should layer/class/type values map to engine-level label categories?
- Are feature ids stable enough for cross-tile identity?

`MapboxVectorTileLabelProviderProfile` should initially reproduce the current
Mapbox-oriented behavior using fields such as `name`, `name_en`, `name_ru`,
`symbolrank`, `sizerank`, `filterrank`, `rank`, `scalerank`, `place_rank`,
`localrank`, and `labelrank`.

## Text Resolution

Text resolution should move out of `TileMvtParser` and into
`VectorTileAdaptation/Labels/Text`.

The first slice should adapt the current settings into internal language
preferences. Existing `.russian` and `.english` settings remain externally
unchanged, but internally become ordered fallback chains.

Glyph coverage must be explicit. A label can be rejected because the current
atlas cannot render its text, but that decision should be isolated so future
atlas expansion or transliteration does not require parser changes.

## Migration Strategy

1. Add the new internal model and provider profile types.
2. Move point/base label text resolution and rank/visibility decisions behind
   `VectorTileLabelDecisionEngine`.
3. Add a small adapter from `VectorTileLabelDecision` to the existing
   `TileMvtParser.TextLabel`.
4. Keep old behavior as close as possible, except for safer identity semantics.
5. Add focused tests for identity generation, language fallback, visibility
   policy, and priority ordering.

## Testing

Add unit tests that do not require Metal:

- provider feature id identity vs tile-local fallback identity
- Mapbox name fallback for Russian and English settings
- glyph coverage rejection for unsupported scripts
- high-level visibility decisions for city, POI, house number, natural, airport,
  and landmark labels
- collision priority ordering for settlement labels vs POI and house numbers

## Open Decisions

The first implementation should keep this layer internal. Public configuration
can be added later after the internal model proves stable with at least one
non-Mapbox provider profile or a clear provider integration requirement.

