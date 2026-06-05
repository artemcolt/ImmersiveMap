# VectorTileAdaptation

`VectorTileAdaptation` is the internal layer that translates provider-specific
vector tile schemas into ImmersiveMap's provider-neutral rendering decisions.

Vector tile providers do not expose labels, feature classes, ranks, names, and
identifiers in the same way. This folder is the boundary where those differences
are interpreted before data reaches renderer-facing tile buffers, label caches,
or draw subsystems.

## Responsibilities

- Normalize provider-specific layer names, feature classes, ranks, and metadata.
- Choose label text from provider-specific name fields and language fallbacks.
- Build stable label identities for deduplication and fade continuity.
- Decide label visibility, collision priority, deduplication priority, and draw
  priority in provider-neutral terms.
- Describe placement intent such as collision padding, anchor behavior, and
  future placement candidates.
- Keep provider-specific rules out of renderer runtime code.

## Non-Responsibilities

- It should not own Metal buffers, render passes, shaders, or frame state.
- It should not perform label fade animation or per-frame collision resolution.
- It should not fetch tiles or configure network authorization.
- It should not expose public API until the internal model is stable.

## Intended Flow

```text
Raw vector tile feature
  -> provider profile
  -> normalized label decision
  -> renderer tile-buffer adapter
  -> existing runtime label cache and draw pipeline
```

The existing `Labels` and `Render/Labels` folders remain responsible for runtime
label state, collision/fade presentation, GPU resources, and drawing. This
folder is for provider adaptation and label decision logic before that runtime
stage.

