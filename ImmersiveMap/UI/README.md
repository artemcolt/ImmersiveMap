# UI

`UI` owns the public UIKit and SwiftUI surfaces plus runtime controllers that
connect user interaction, camera commands, selection, settings, tiles, and
rendering.

This folder is the integration layer for app-facing usage. It should coordinate
engine subsystems without taking over their internal responsibilities.

## Responsibilities

- Expose public UIKit and SwiftUI map views.
- Own runtime graph construction for the interactive map surface.
- Handle gestures, controls, camera commands, selection events, and viewport
  updates.
- Connect render driver pacing with engine runtime controllers.
- Provide test-support hooks for UI-level integration behavior.

## May Contain

- Public `UIView` and `UIViewRepresentable` entry points.
- UIKit controls, gesture controllers, and interaction runtimes.
- Camera, selection, avatar, viewport, controls, and render runtime controllers.
- Render loop pacing and render driver delegates.
- Public UI-facing controller types.

## Must Not Contain

- Metal pipeline creation, shader files, render graph internals, or GPU resource
  lifetime that belongs in `Render`.
- Raw tile parsing, feature styling, disk caching internals, or MVT decode code.
- Provider-specific label adaptation or language fallback policy.
- Host-app-only app delegates, scene setup, launch environment parsing, or demo
  mode code.
- Bearer tokens, Mapbox tokens, private endpoints, or local secret files.

## Intended Flow

```text
App-facing map view
  -> UI runtime graph
  -> interaction, camera, tile, avatar, and selection controllers
  -> render driver
  -> Render frame engine
```
