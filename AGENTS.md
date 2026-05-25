# Repository Guidelines

## Project Context

This repository is `artemcolt/ImmersiveMap`: a public standalone Swift Package extracted from Tucik iOS `ImmersiveMapFramework`.

- Local path: `/Users/artembobkin/Desktop/ImmersiveMap`
- Public GitHub URL: `https://github.com/artemcolt/ImmersiveMap`
- Default branch: `main`
- Main product: Swift Package library product `ImmersiveMap`
- Minimum platform: iOS 18.0

The package contains the Metal renderer, vector tile pipeline, globe/flat presentation, labels, trees, and avatar markers. Keep rendering changes scoped and validate with an iOS Simulator build.

## Current Handoff State

The current in-progress work is adding runnable screenshots and README documentation.

Uncommitted work expected in this handoff:

- `README.md` includes a new `Screenshots` section and `Demo App` section.
- `Docs/Screenshots/immersive-map-city.png` and `Docs/Screenshots/immersive-map-globe.png` contain verified simulator screenshots.
- `Examples/ImmersiveMapDemo/` contains a small SwiftUI demo app used to run the map.
- `.gitignore` was updated to ignore nested `DerivedData/`.

Do not commit build artifacts:

- `.build/`
- `DerivedData/`
- `Examples/ImmersiveMapDemo/DerivedData/`

## Demo App

The runnable demo app lives at:

```text
Examples/ImmersiveMapDemo/ImmersiveMapDemo.xcodeproj
```

It has one app target/scheme:

```text
ImmersiveMapDemo
```

The demo intentionally uses the public package URL dependency:

```text
https://github.com/artemcolt/ImmersiveMap.git
```

That mirrors the external-user install path. If you need to test unpublished local package changes inside the demo, either push the package first or temporarily switch the demo package dependency to a local package reference, then revert before publishing.

The demo reads optional launch environment variables:

```text
IMMERSIVE_MAP_TILE_BASE_URL=https://example.com/api/v1/map/tiles
IMMERSIVE_MAP_AUTH_TOKEN=your-token
```

Never commit real bearer tokens, stand secrets, database credentials, Mapbox tokens, or generated secret files.

## Screenshot Workflow

Use XcodeBuildMCP when available for Simulator build/run/screenshot.

Known working session defaults:

```text
projectPath=/Users/artembobkin/Desktop/ImmersiveMap/Examples/ImmersiveMapDemo/ImmersiveMapDemo.xcodeproj
scheme=ImmersiveMapDemo
configuration=Debug
simulatorName=iPhone 17 Pro
useLatestOS=true
derivedDataPath=/Users/artembobkin/Desktop/ImmersiveMap/Examples/ImmersiveMapDemo/DerivedData
bundleId=com.artemcolt.ImmersiveMapDemo
```

The demo builds and launches successfully on the simulator. The stand tile endpoint currently requires auth. Without `IMMERSIVE_MAP_AUTH_TOKEN`, the app still launches and renders markers, but protected Tucik tiles return `401`.

To launch the installed simulator app with a local-only token:

```bash
SIMCTL_CHILD_IMMERSIVE_MAP_AUTH_TOKEN="$TOKEN" \
  xcrun simctl launch booted com.artemcolt.ImmersiveMapDemo
```

After screenshots are captured, place final README images here:

```text
Docs/Screenshots/immersive-map-city.png
Docs/Screenshots/immersive-map-globe.png
```

The existing screenshots were visually checked:

- `immersive-map-city.png`: Moscow city/flat map view with avatar marker.
- `immersive-map-globe.png`: globe view with starfield/background and avatar marker.

## Validation

Commands/run status from this handoff:

- `xcodebuild -scheme ImmersiveMap -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build` previously succeeded for the package.
- XcodeBuildMCP `build_run_sim` succeeded for `ImmersiveMapDemo` after adding screenshots/demo docs.
- Secret scan was run with `rg` patterns for known local secret fragments and found no matches in source text outside ignored/generated artifacts.

Before final handoff or push:

1. Run `git status --short --ignored` and confirm build artifacts are ignored.
2. Run a final secret scan over tracked source/docs, excluding PNGs and DerivedData.
3. Build the package and/or demo app.
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
