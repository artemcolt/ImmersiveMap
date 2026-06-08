# Text

`Text` owns text atlas parsing, glyph metrics, text layout inputs, and CPU-side
helpers used before label text reaches renderer draw code.

This folder should focus on text data and geometry preparation, not label policy
or provider-specific name selection.

## Responsibilities

- Decode text atlas and glyph metric data.
- Measure, wrap, and prepare label text geometry inputs.
- Define text and label vertex data shared with renderer consumers.
- Keep text layout behavior independent of vector tile provider schemas.

## May Contain

- Text atlas models and resource readers.
- Glyph, bounds, metrics, and text sizing types.
- Text layout, wrapping, and alignment helpers.
- CPU-side vertex and uniform structs for text rendering.

## Must Not Contain

- Provider-specific language fallback or label text field selection.
- Runtime label cache ownership, collision state, or fade animation policy.
- Metal render passes, pipeline creation, or shader files.
- Tile network loading, disk caching, or MVT parsing.
- UI controls, host-app code, tokens, or local secrets.

## Intended Flow

```text
Text resources and label strings
  -> glyph metrics and layout
  -> prepared text vertices
  -> renderer text draw code
```
