# Project Tree

This file documents the main directories and modules in the repository. Please keep it up to date when structure changes.

## Top Level

```
.
├── AGENTS.md                      - Agent instructions for this repo
├── ImmersiveMap                   - App target (UI shell + app wiring)
├── ImmersiveMap.xcodeproj         - Xcode project
├── ImmersiveMapFramework          - Core map engine (Swift + Metal)
├── ai                             - Internal notes/tasks
├── documentation                  - Project docs (see TILE_SPECIFICATION.md)
└── todo.txt                       - Local task notes
```

## ImmersiveMapFramework (Core Engine)

```
ImmersiveMapFramework
├── Camera/                        - Camera model + controls
├── Globe/                         - Globe rendering, starfield, pipelines
├── Labels/                        - Label state, cache, and draw metadata
├── Render/                        - Render loop, pipelines, screen-matrix utilities
├── ScreenCompute/                 - Screen-space compute and collision passes
├── Shaders/                       - Metal shaders + shared headers
├── Tile/                          - Tile parsing, placement, and Metal buffers
├── Text/                          - Text layout + MSDF rendering helpers
├── Texture/                       - Texture handling (tiles/atlas)
└── ImmersiveMapView.swift         - Public view API
```

## Key Modules (ImmersiveMapFramework)

- Renderer
  - `ImmersiveMapFramework/Render/Renderer.swift`: main render loop; dispatches pipelines and compute passes.
- Camera
  - `ImmersiveMapFramework/Camera`: camera state, projection, input handling.
- Globe
  - `ImmersiveMapFramework/Globe`: globe mesh, starfield, and globe pipelines.
- Labels
  - `ImmersiveMapFramework/Labels`: label cache, runtime state, and draw metadata.
- Render
  - `ImmersiveMapFramework/Render`: render orchestration, pipelines, screen transforms.
- ScreenCompute
  - `ImmersiveMapFramework/ScreenCompute`: screen-point compute, collisions, and state updates.
- Shaders
  - `ImmersiveMapFramework/Shaders`: Metal shaders; `Screen/` contains screen-point compute and collisions.
- Tile
  - `ImmersiveMapFramework/Tile`: vector tile parsing, placement, and GPU buffers.
- Text
  - `ImmersiveMapFramework/Text`: text layout + MSDF rendering support.
