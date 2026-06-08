# Starfield

`Starfield` owns the CPU-side model used to describe stars before they are drawn
by renderer starfield code.

This folder is intentionally small. Rendering ownership belongs in
`Render/Starfield`.

## Responsibilities

- Define deterministic starfield model data.
- Provide star value types shared with rendering setup.
- Keep starfield content independent of map tiles and providers.

## May Contain

- Starfield model generators and value types.
- Pure math for deterministic star placement.
- Public-safe constants for star distribution or appearance.

## Must Not Contain

- Metal pipelines, shader files, render passes, or GPU buffer management.
- Tile loading, parsing, styling, or provider adaptation.
- Camera controllers, UI gestures, or host-app code.
- Secrets, network endpoints, or local configuration.
- Non-starfield visual models.

## Intended Flow

```text
Starfield model
  -> renderer starfield pipeline
  -> drawable background
```
