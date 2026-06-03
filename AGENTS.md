# Repository Guidelines

## Project Context

This repository is `artemcolt/ImmersiveMap`: a public standalone Swift Package for the ImmersiveMap engine.

- Local path: `/Users/artembobkin/Desktop/ImmersiveMap`
- Public GitHub URL: `https://github.com/artemcolt/ImmersiveMap`
- Default branch: `main`
- Main product: Swift Package library product `ImmersiveMap`
- Minimum platform: iOS 18.0 and Mac Catalyst 18.0

The package contains the Metal renderer, vector tile pipeline, globe/flat presentation, labels, trees, and avatar markers. Keep rendering changes scoped and validate with an iOS Simulator build.

## Source File Headers

Every hand-written `.swift`, `.metal`, `.h`, and `.proto` source file should start with:

```text
// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT
```

Do not add this header to generated files such as `ImmersiveMap/Generated/Proto/vector_tile.pb.swift`.

## User Intent Rules

When the user writes `исследуй` or asks to investigate/research, treat it as a read-only request. Do not edit files, implement changes, run mutating commands, or change generated/tracked artifacts unless the user explicitly asks for implementation after the investigation.

## Current Handoff State

The current in-progress work is adding runnable screenshots and README documentation.

Uncommitted work expected in this handoff:

- `README.md` includes a new `Screenshots` section and `Xcode Workspace` section.
- `Docs/Screenshots/immersive-map-city.png`, `Docs/Screenshots/immersive-map-globe.png`, and `Docs/Screenshots/immersive-map-moscow-closeup.png` contain verified simulator screenshots.
- `ImmersiveMap/` contains the Swift Package target sources and resources.
- `ImmersiveMapIOS/` contains an iOS host app used to run the map.
- `ImmersiveMapMac/` contains a Mac Catalyst host app used to run the map on Mac.
- `ImmersiveMap.xcworkspace` opens the package and host apps together.
- `.gitignore` was updated to ignore nested `DerivedData/`.

Do not commit build artifacts:

- `.build/`
- `DerivedData/`
- `ImmersiveMapIOS/DerivedData/`
- `ImmersiveMapMac/DerivedData/`

## Host Apps

The runnable host apps live at:

```text
ImmersiveMapIOS/ImmersiveMapIOS.xcodeproj
ImmersiveMapMac/ImmersiveMapMac.xcodeproj
```

Open the workspace for day-to-day development:

```text
ImmersiveMap.xcworkspace
```

It has app schemes:

```text
ImmersiveMapIOS
ImmersiveMapMac
```

Both host apps intentionally use a local package reference so unpublished package changes can be run immediately.

The host apps read optional launch environment variables:

```text
IMMERSIVE_MAP_TILE_BASE_URL=https://example.com/api/v1/map/tiles
IMMERSIVE_MAP_AUTH_TOKEN=your-token
IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN=your-mapbox-public-token
IMMERSIVE_MAP_MAPBOX_TILESET_ID=mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2
IMMERSIVE_MAP_DEMO_MODE=city|globe|moscowCloseup
```

If `IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN` is present, the host apps use the Mapbox Vector Tiles API and pass the token as the `access_token` query parameter. Never commit real bearer tokens, stand secrets, database credentials, Mapbox tokens, or generated secret files.

## Screenshot Workflow

Use XcodeBuildMCP when available for Simulator build/run/screenshot.

Known working session defaults:

```text
workspacePath=/Users/artembobkin/Desktop/ImmersiveMap/ImmersiveMap.xcworkspace
scheme=ImmersiveMapIOS
configuration=Debug
simulatorName=iPhone 17 Pro
useLatestOS=true
derivedDataPath=/Users/artembobkin/Desktop/ImmersiveMap/DerivedData
bundleId=com.artemcolt.ImmersiveMapIOS
```

The host app builds and launches successfully on the simulator. If the configured tile endpoint requires auth, the app still launches and renders markers without `IMMERSIVE_MAP_AUTH_TOKEN`, but protected tiles return `401`.

To launch the installed simulator app with a local-only token:

```bash
SIMCTL_CHILD_IMMERSIVE_MAP_AUTH_TOKEN="$TOKEN" \
  xcrun simctl launch booted com.artemcolt.ImmersiveMapIOS
```

After screenshots are captured, place final README images here:

```text
Docs/Screenshots/immersive-map-city.png
Docs/Screenshots/immersive-map-globe.png
Docs/Screenshots/immersive-map-moscow-closeup.png
```

The existing screenshots were visually checked:

- `immersive-map-city.png`: Moscow city/flat map view with avatar marker.
- `immersive-map-globe.png`: globe view with starfield/background and avatar marker.
- `immersive-map-moscow-closeup.png`: high-zoom angled Moscow view with 3D buildings.

## Validation

Commands/run status from this handoff:

- `xcodebuild -scheme ImmersiveMap -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build` previously succeeded for the package.
- XcodeBuildMCP `build_run_sim` succeeded for the host app after adding screenshots and workspace docs.
- Secret scan was run with `rg` patterns for known local secret fragments and found no matches in source text outside ignored/generated artifacts.

Before final handoff or push:

1. Run `git status --short --ignored` and confirm build artifacts are ignored.
2. Run a final secret scan over tracked source/docs, excluding PNGs and DerivedData.
3. Build the package and/or host apps.
4. Commit and push the public-safe changes to `main` if the user wants the README updates live on GitHub.

## Public README Notes

Keep README examples generic:

- Use `https://example.com/api/v1/map/tiles` in install/use snippets.
- Mention bearer token configuration without including real values.
- Keep screenshots linked as relative paths under `Docs/Screenshots`.

## Security

This repo is public. Treat anything committed here as public internet content.

Do not commit:

- Device/session bearer tokens.
- Simulator dev auth secrets.
- Database passwords or connection strings.
- APNS private key data.
- Mapbox access tokens.
- Local `Downloads` stand notes.
- `LocalSecrets.plist` or any equivalent runtime secret file.
