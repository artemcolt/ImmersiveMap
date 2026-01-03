

# Repository Guidelines
You are a senior Metal + IOS mobile engineer.

## Project Structure & Module Organization
- `ImmersiveMap/` contains the app entry point and assets (e.g., `ImmersiveMapApp.swift`, `Assets.xcassets`).
- `ImmersiveMapFramework/` holds the core rendering and map logic.
  - `Shaders/` contains Metal shaders (`*.metal`, shared types in `Common.h`).
  - `Globe/` contains globe rendering and tile visibility logic.
  - `Tile/` contains tile downloading, caching, parsing, and styling.
  - `Camera/` contains camera state and controls.
  - `Text/` contains glyph atlas resources and text rendering.
- `ImmersiveMapFramework/ImmersiveMapFramework.docc/` contains framework documentation.

## Build, Test, and Development Commands
- `open ImmersiveMap.xcodeproj` opens the project in Xcode.
- `xcodebuild -project ImmersiveMap.xcodeproj -scheme ImmersiveMap -configuration Debug build` builds the app from the command line.
- Run from Xcode for the fastest iteration on Metal shaders and UI.

## Coding Style & Naming Conventions
- Swift uses 4-space indentation and standard Swift naming: `PascalCase` for types and `camelCase` for members.
- Keep file names aligned with primary types (e.g., `GlobePipeline.swift`).
- Metal shader files live in `ImmersiveMapFramework/Shaders/`; keep shared structs in `Common.h` and keep shader functions small and focused.
- Prefer concise comments only where math or rendering logic is non-obvious.

## Testing Guidelines
- No test targets are present in this repository. If adding tests, use `XCTest` and name files `SomethingTests.swift`.

## Commit & Pull Request Guidelines
- Recent commit messages are uniformly `dev`; there is no established convention. Use short, imperative messages (e.g., "Fix globe UV clamp") unless the team agrees to change the pattern.
- PRs should include a concise summary, steps to verify, and screenshots or screen recordings for rendering or UI changes.

## Communication Guidelines
- Keep in mind the maintainer is not a native English speaker.
- First, check the English in which your query was written, and keep wording simple and clear.

## Configuration Tips
- Tile downloads use Mapbox and require `MAPBOX` in the environment (`MAPBOX=<token>`).
