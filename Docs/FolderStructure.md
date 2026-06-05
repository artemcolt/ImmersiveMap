# Folder Structure

The `ImmersiveMap` target uses a layered structure for runtime code. Files should be placed by responsibility, not by the object or feature that happens to use them first.

## Folder Kinds

### Domain Folders

Use domain folders for focused runtime concepts that own their own state, behavior, constraints, and transformations.

Place code in a domain folder when it describes what the concept is, which states it can have, and how it changes without depending on UI controls, platform views, render passes, or GPU resources.

### Render

Use `Render` for frame rendering and renderer-facing preparation.

Place code here when it prepares or executes a frame, resolves render-time state, builds renderer inputs, handles render visibility, encodes render work, or produces data consumed by GPU-facing code.

### UI

Use `UI` for platform integration and user interaction.

Place code here when it owns views, controls, gestures, interaction handlers, display-link or render-loop integration, runtime wiring, platform adapters, or user-facing commands.

### Utils

Use `Utils` for small shared helpers.

Place code here only when it is dependency-light, reusable across layers, and not owned by a more specific folder. Prefer pure functions and small utilities. Do not use `Utils` as a fallback for code with unclear ownership.

## Dependency Direction

Dependencies should generally point inward from integration code toward domain and shared code:

```text
UI -> Domain folders
UI -> Render
Render -> Domain folders
Domain folders -> Utils
Render -> Utils
UI -> Utils
```

Avoid reverse dependencies:

- Domain folders should not depend on `UI` or `Render`.
- `Render` should not depend on `UI`.
- `Utils` should not depend on runtime, rendering, platform, or feature-specific code.

## Placement Rules

Before adding or moving a file, choose the folder by the responsibility it owns:

1. If it is platform, view, gesture, control, interaction, or runtime wiring code, put it in `UI`.
2. If it is renderer-facing frame preparation or frame execution code, put it in `Render`.
3. If it is domain-level state or behavior for a focused runtime concept, put it in that concept's domain folder.
4. If it is a small shared helper with no stronger owner, put it in `Utils`.

If a file fits several folders, split it by responsibility. A file that needs to live in multiple layers usually contains more than one concern.

## Boundary Rules

- Keep UI translation separate from domain behavior.
- Keep frame rendering separate from platform interaction.
- Keep shared helpers small and dependency-light.
- Prefer explicit layer ownership over broad helper objects.
- Do not move feature-specific code into broad folders only to make the structure look complete.

## Naming Rules

Names should describe the role of a type in its layer:

- Use `...State` for value-like state containers.
- Use `...Controller` for coordination of commands or interactions.
- Use `...Resolver` for deterministic conversion from input state to output state.
- Use `...Runtime` for long-lived objects that wire dependencies together.
- Use `...Math` for stateless calculations.

Avoid vague names such as `Manager`, `Helper`, or `Service` unless the surrounding code gives the term a precise and consistent meaning.
