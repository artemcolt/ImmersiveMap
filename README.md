# ImmersiveMap

![ImmersiveMap hero](Documentation/Assets/immersive-map-hero.png)

Swift + Metal map engine for SwiftUI.

## Add To Xcode

In Xcode, select `File` -> `Add Package Dependencies...` and add:

```text
https://github.com/artemcolt/ImmersiveMap.git
```

Then add the `ImmersiveMap` product to your app target.

## SwiftUI

```swift
import SwiftUI
import ImmersiveMap

struct ContentView: View {
    @State private var camera = ImmersiveMapCameraController()
    private let tileProvider = MapboxTileProvider(accessToken: "your-mapbox-public-token")
    private let mapStyle = MapboxMapStyle()

    var body: some View {
        ImmersiveMapView()
            .camera(
                camera,
                position: ImmersiveMapCameraPosition(
                    latitudeDegrees: 55.7558,
                    longitudeDegrees: 37.6173,
                    zoom: 0
                )
            )
            .tileProvider(tileProvider)
            .mapStyle(mapStyle)
            .ignoresSafeArea()
    }
}
```
