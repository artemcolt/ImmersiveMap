# ImmersiveMap

ImmersiveMap is a standalone iOS and Mac Catalyst Metal map engine.

## Requirements

- iOS 18.0+
- Mac Catalyst 18.0+
- Xcode with Metal support
- Swift Package Manager

## Installation

In Xcode:

1. Open your app project.
2. Select `File` -> `Add Package Dependencies...`.
3. Enter:

```text
https://github.com/artemcolt/ImmersiveMap.git
```

4. Add the `ImmersiveMap` product to your app target.

If you manage dependencies in `Package.swift`, add:

```swift
.package(url: "https://github.com/artemcolt/ImmersiveMap.git", branch: "main")
```

Then add the product to your target:

```swift
.product(name: "ImmersiveMap", package: "ImmersiveMap")
```

## Tile Server

ImmersiveMap renders Mapbox Vector Tile (`.mvt`) data. You must provide a tile endpoint that returns vector tiles at this URL shape:

```text
{tileBaseURL}/{z}/{x}/{y}.mvt
```

For example, if `tileBaseURL` is:

```text
https://example.com/api/v1/map/tiles
```

the map will request:

```text
https://example.com/api/v1/map/tiles/12/2411/1539.mvt
```

Configure the endpoint by passing a provider to `.provider(...)`. For a generic vector tile endpoint, use `CustomVectorTileProvider` with `ImmersiveMapTileSource.url(...)`; if your tile server requires a bearer token, add `.token(...)`.

## Xcode Workspace

Open `ImmersiveMap.xcworkspace` when you want to work on the map engine and run a test app from the same Xcode window.

The workspace contains:

- `ImmersiveMap`: the local Swift Package target under `ImmersiveMap/`.
- `ImmersiveMapIOS`: an iOS host app for Simulator/device testing.
- `ImmersiveMapMac`: a Mac Catalyst host app for running on Mac.

Both host apps link the local package checkout, so changes under `ImmersiveMap/` are built directly into the app.

The host apps read one optional launch environment variable:

```text
IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN=your-mapbox-public-token
```

Do not commit Mapbox tokens. Use Xcode scheme environment variables, or launch the installed simulator app with `SIMCTL_CHILD_IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN` when you need to test Mapbox-hosted vector tiles.

When `IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN` is present, the host apps request tiles from `https://api.mapbox.com/v4/{tileset_id}/{z}/{x}/{y}.mvt?access_token=...`. The default Mapbox tileset ID is `mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2`.

## SwiftUI Quick Start

```swift
import SwiftUI
import ImmersiveMap

struct MapScreen: View {
    @State private var camera = ImmersiveMapCameraController()
    private let avatars = ImmersiveMapAvatarsController()

    var body: some View {
        ImmersiveMapView()
            .avatars(avatars)
            .camera(
                camera,
                position: .init(
                    latitudeDegrees: 55.7558,
                    longitudeDegrees: 37.6173,
                    zoom: 12,
                    bearing: 0,
                    pitch: 0
                )
            )
            .provider(
                CustomVectorTileProvider(
                    id: "example",
                    tileSource: .url(URL(string: "https://example.com/api/v1/map/tiles")!),
                    style: BasicVectorTileStyle()
                )
            )
            .ignoresSafeArea()
    }
}
```

## UIKit Quick Start

```swift
import UIKit
import ImmersiveMap

final class MapViewController: UIViewController {
    private let camera = ImmersiveMapCameraController()
    private let avatars = ImmersiveMapAvatarsController()

    override func viewDidLoad() {
        super.viewDidLoad()

        let settings = ImmersiveMapSettings.default
            .provider(
                CustomVectorTileProvider(
                    id: "example",
                    tileSource: .url(URL(string: "https://example.com/api/v1/map/tiles")!),
                    style: BasicVectorTileStyle()
                )
            )

        let mapView = ImmersiveMapUIView(
            frame: view.bounds,
            settings: settings,
            avatarsController: avatars,
            cameraPosition: .init(
                latitudeDegrees: 55.7558,
                longitudeDegrees: 37.6173,
                zoom: 12
            )
        )

        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        camera.attach(mapView: mapView)
    }
}
```

## Camera Control

Keep an `ImmersiveMapCameraController` and attach it with `.camera(...)`.

```swift
let camera = ImmersiveMapCameraController()

camera.jump(to: .init(
    latitudeDegrees: 48.8566,
    longitudeDegrees: 2.3522,
    zoom: 13
))

camera.fly(to: .init(
    latitudeDegrees: 40.7128,
    longitudeDegrees: -74.0060,
    zoom: 11,
    bearing: .pi / 7,
    pitch: .pi / 4
))
```

`latitudeDegrees` and `longitudeDegrees` use degrees. `bearing`, `pitch`, and camera pitch settings use radians.

## Avatar Markers

Use `ImmersiveMapAvatarsController` to show moving people, vehicles, or other live objects on the map.

```swift
import UIKit
import ImmersiveMap

let avatars = ImmersiveMapAvatarsController()

avatars.set([
    AvatarMarker(
        id: 1,
        coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
        image: UIImage(named: "avatar")!,
        batteryBadge: AvatarBatteryBadge(levelPct: 82),
        speedBadge: AvatarSpeedBadge(kilometersPerHour: 5),
        isSelected: true
    )
])

avatars.move(id: 1, latitude: 55.7562, longitude: 37.6180)
```

## Selection

Attach an `ImmersiveMapSelectionController` if you need callbacks when users tap map objects or empty background.

```swift
let selection = ImmersiveMapSelectionController()

selection.onSelectionChanged = { event in
    print("Selected:", event.selection)
}

selection.onSelectionCleared = { event in
    print("Cleared:", event.previousSelection)
}

selection.onMapBackgroundTap = { point in
    print("Background tap:", point)
}
```

Pass it into SwiftUI:

```swift
ImmersiveMapView()
    .selection(selection)
    .provider(
        CustomVectorTileProvider(
            id: "example",
            tileSource: .url(URL(string: "https://example.com/api/v1/map/tiles")!),
            style: BasicVectorTileStyle()
        )
    )
```

## Common Configuration

```swift
ImmersiveMapView()
    .provider(
        CustomVectorTileProvider(
            id: "example",
            tileSource: .url(URL(string: "https://example.com/api/v1/map/tiles")!)
                .token("your-token"),
            style: BasicVectorTileStyle()
        )
    )

ImmersiveMapView()
    .provider(MapboxProvider(accessToken: "your-mapbox-public-token"))

ImmersiveMapView()
    .provider(OpenStreetMapProvider())
```

Use fluent settings modifiers when you need to tune lower-level renderer, cache, label, or camera settings:

```swift
let labels = ImmersiveMapSettings.default.labels
let camera = ImmersiveMapSettings.default.camera

ImmersiveMapView()
    .provider(
        CustomVectorTileProvider(
            id: "example",
            tileSource: .url(URL(string: "https://example.com/api/v1/map/tiles")!)
                .token("your-token"),
            style: BasicVectorTileStyle()
        )
    )
    .labelSettings(
        .init(
            language: .french,
            fallbackPolicy: .international,
            houseNumbers: labels.houseNumbers,
            settlementVisibility: labels.settlementVisibility,
            landmarks: labels.landmarks,
            base: labels.base,
            road: labels.road
        )
    )
    .cameraSettings(
        .init(
            maximumPitch: Float.pi * 65 / 180,
            maximumZoom: 18,
            focusedMarkerZoom: camera.focusedMarkerZoom,
            globeMinimumAbsoluteBearing: camera.globeMinimumAbsoluteBearing,
            globeBearingUnlockZoom: camera.globeBearingUnlockZoom,
            globePitchUnlockZoom: camera.globePitchUnlockZoom,
            highZoomPitchExtension: camera.highZoomPitchExtension,
            highZoomPitchExtensionStartZoom: camera.highZoomPitchExtensionStartZoom,
            highZoomPitchExtensionEndZoom: camera.highZoomPitchExtensionEndZoom,
            extraHighZoomPitchExtension: camera.extraHighZoomPitchExtension,
            extraHighZoomPitchExtensionStartZoom: camera.extraHighZoomPitchExtensionStartZoom,
            extraHighZoomPitchExtensionEndZoom: camera.extraHighZoomPitchExtensionEndZoom,
            gesturePanTranslationScale: camera.gesturePanTranslationScale,
            worldPanSensitivity: camera.worldPanSensitivity,
            worldPanSpeed: camera.worldPanSpeed,
            pinchZoomFactor: camera.pinchZoomFactor,
            pinchZoomVelocityFactor: camera.pinchZoomVelocityFactor,
            pinchZoomVelocityLimit: camera.pinchZoomVelocityLimit,
            dragZoomFactor: camera.dragZoomFactor,
            dragZoomVelocityFactor: camera.dragZoomVelocityFactor,
            dragZoomVelocityLimit: camera.dragZoomVelocityLimit,
            rotationGestureSensitivity: camera.rotationGestureSensitivity,
            globePanInertiaEnabled: camera.globePanInertiaEnabled,
            globePanInertiaHalfLife: camera.globePanInertiaHalfLife,
            globePanInertiaActivationVelocity: camera.globePanInertiaActivationVelocity,
            globePanInertiaStopVelocity: camera.globePanInertiaStopVelocity,
            globePanInertiaMaxInitialVelocity: camera.globePanInertiaMaxInitialVelocity
        )
    )
    .debugPanel(false)
```

### Mapbox Default Map Style

Pass a configured `MapboxProvider` to tune common rendering tokens for the built-in Mapbox-compatible renderer:

```swift
let style = MapboxDefaultMapStyleConfiguration.mapboxDefault
    .layers { layers in
        layers.water = SIMD4<Float>(0.35, 0.58, 0.78, 1.0)
        layers.park = SIMD4<Float>(0.50, 0.70, 0.48, 0.75)
        layers.roads.major = SIMD4<Float>(0.95, 0.88, 0.76, 1.0)
        layers.roads.footway = SIMD4<Float>(0.92, 0.92, 0.88, 1.0)
    }
    .labels { labels in
        labels.district.strokeWidthPx = 2.0
        labels.poi.strokeWidthPx = 6.0
        labels.road.fillColor = SIMD3<Float>(0.48, 0.48, 0.46)
    }
    .features { features in
        features.buildingFillColor = SIMD4<Float>(0.94, 0.91, 0.86, 1.0)
    }

ImmersiveMapView()
    .provider(MapboxProvider(accessToken: "your-mapbox-public-token", style: style))
```

Changing map style tokens invalidates prepared tile cache entries automatically.

### OpenStreetMap Default Map Style

`OpenStreetMapProvider` uses the OSMF Shortbread vector tile endpoint by default:

```swift
ImmersiveMapView()
    .provider(OpenStreetMapProvider())
```

Tune the built-in Shortbread-compatible renderer with `OpenStreetMapDefaultMapStyleConfiguration.osmDefault`:

```swift
let style = OpenStreetMapDefaultMapStyleConfiguration.osmDefault
    .layers { layers in
        layers.water = SIMD4<Float>(0.35, 0.58, 0.78, 1.0)
        layers.park = SIMD4<Float>(0.50, 0.70, 0.48, 0.75)
        layers.roads.major = SIMD4<Float>(0.95, 0.88, 0.76, 1.0)
    }
    .labels { labels in
        labels.place.strokeWidthPx = 2.0
        labels.poi.strokeWidthPx = 2.0
        labels.road.fillColor = SIMD3<Float>(0.48, 0.48, 0.46)
    }
    .features { features in
        features.buildingFillColor = SIMD4<Float>(0.94, 0.91, 0.86, 1.0)
    }

ImmersiveMapView()
    .provider(OpenStreetMapProvider(style: style))
```

The default URL is `https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt`. `OpenStreetMapProvider` also limits tile coverage to Shortbread's max zoom 14. Follow the [OSMF Vector Tile Usage Policy](https://operations.osmfoundation.org/policies/vector/) for attribution, User-Agent, caching, and traffic limits.

## Build This Package

```bash
xcodebuild \
  -scheme ImmersiveMap \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  build
```

For Mac Catalyst:

```bash
xcodebuild \
  -scheme ImmersiveMap \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath DerivedData \
  build
```

## Notes

- The package contains Metal shaders and runtime resources. Always add it as a Swift Package product, not by copying individual Swift files.
- The tile parser is designed for vector tiles with layers and attributes used by the engine's style system. If your tile source uses a different schema, you may need to adjust parsing or styling code.
- Production apps should explicitly set `.provider(...)` and cache/network settings.

## License

MIT. See [LICENSE](LICENSE).
