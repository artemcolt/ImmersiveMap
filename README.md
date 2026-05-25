# ImmersiveMap

ImmersiveMap is the standalone Metal map engine extracted from the Tucik iOS app.

It provides:

- `ImmersiveMapView` for SwiftUI.
- `ImmersiveMapUIView` for UIKit.
- Flat and globe rendering modes.
- Vector tile loading/parsing, labels, POI icons, buildings, trees, and avatar markers.
- Runtime map configuration through `MapSettings`.

## Requirements

- iOS 18.0+
- Xcode with Metal support
- Swift Package Manager

## Installation

Add this repository as a Swift Package dependency and link the `ImmersiveMap` product.

```swift
.package(url: "git@github.com:artemcolt/ImmersiveMap.git", branch: "main")
```

## Basic Usage

```swift
import SwiftUI
import ImmersiveMap

struct MapScreen: View {
    var body: some View {
        ImmersiveMapView(settings: .default)
            .ignoresSafeArea()
    }
}
```

Configure tile loading with `MapSettings.TileSettings.NetworkSettings`:

```swift
var settings = MapSettings.default
settings.tiles.network.tileBaseURL = URL(string: "https://example.com/api/v1/map/tiles")!
settings.tiles.network.authorizationToken = "<bearer-token>"
```

## Build

```bash
xcodebuild \
  -scheme ImmersiveMap \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  build
```

## Origin

Extracted from `TucikIosMobile/ImmersiveMapFramework`.
