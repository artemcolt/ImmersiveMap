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

Configure the endpoint with `ImmersiveMapTileSource.url(...)`. If your tile server requires a bearer token, add `.token(...)`. If it does not require authentication, leave the token as `nil`.

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
        ImmersiveMapView(
            avatarsController: avatars,
            cameraPosition: .init(
                latitudeDegrees: 55.7558,
                longitudeDegrees: 37.6173,
                zoom: 12,
                bearing: 0,
                pitch: 0
            ),
            cameraController: camera
        )
        .tileSource(.url(URL(string: "https://example.com/api/v1/map/tiles")!))
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
            .tileSource(.url(URL(string: "https://example.com/api/v1/map/tiles")!))

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

Keep an `ImmersiveMapCameraController` and pass it to `ImmersiveMapView`.

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

Attach a `MapSelectionController` if you need callbacks when users tap map objects or empty background.

```swift
let selection = MapSelectionController()

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
ImmersiveMapView(
    selectionController: selection
)
.tileSource(
    .url(URL(string: "https://example.com/api/v1/map/tiles")!)
)
```

## Common Configuration

```swift
ImmersiveMapView()
    .tileSource(
        .url(URL(string: "https://example.com/api/v1/map/tiles")!)
            .token("your-token")
    )

ImmersiveMapView()
    .tileSource(.mapbox(accessToken: "your-mapbox-public-token"))
```

Use `ImmersiveMapSettings` directly when you need to tune lower-level renderer, cache, label, or camera settings:

```swift
var settings = ImmersiveMapSettings.default
    .tileSource(
        .url(URL(string: "https://example.com/api/v1/map/tiles")!)
            .token("your-token")
    )

settings.tiles.network.maxConcurrentFetches = 6
settings.labels.language = .french
settings.labels.fallbackPolicy = .international
settings.renderLoop.forceContinuousRendering = false
settings.camera.maximumZoom = 18
settings.camera.maximumPitch = Float.pi * 65 / 180
settings.debug.enableDebugPanel = false
```

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
- The default settings are suitable for development, but production apps should explicitly set `tileBaseURL` and cache/network settings.

## License

MIT. See [LICENSE](LICENSE).
