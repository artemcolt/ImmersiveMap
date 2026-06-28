# Night Lights Tiles Local Storage

Local MinIO setup for serving ImmersiveMap night-light tile manifests and tile objects.

## Run

```sh
cd Server/NightLightsTiles
docker compose up -d
```

API: `http://localhost:9000`

Console: `http://localhost:9001`

Default local credentials:

```text
MINIO_ROOT_USER=immersivemap
MINIO_ROOT_PASSWORD=immersivemap-local-dev
```

## Manifest

```sh
curl http://localhost:9000/night-lights/v1/night_lights_manifest.json
```

Tile URL template from the manifest:

```text
http://localhost:9000/night-lights/v1/tiles/night_lights_{z}_{x}_{y}.jpg
```

SwiftUI configuration:

```swift
ImmersiveMapView()
    .nightLightsTileManifestURL(
        URL(string: "http://localhost:9000/night-lights/v1/night_lights_manifest.json")
    )
```

The init container seeds `v1/tiles/` from the package's current bundled night-light JPEG resources.
The `seed/night-lights/v1/tiles/` directory is intentionally ignored except for `.gitkeep`; generated or external tile payloads should not be committed there.
