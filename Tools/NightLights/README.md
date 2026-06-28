# Night Lights Tile Generator

This tool generates server-hosted tile payloads used by `NightLightsTileSet`.
It converts NASA Black Marble 2016 grayscale 500m source imagery into flat tile
filenames:

```text
night_lights_<z>_<x>_<y>.jpg
night_lights_generation_metadata.json
```

The local MinIO seed manifest uses the same flat filename convention in
`tileURLTemplate`.

## Source Data

Source page:

```text
https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/
```

Use the `2016 Grayscale` `Full Resolution (500m), tiled` JPEG sources. Expected
source files are:

```text
BlackMarble_2016_A1_gray.jpg
BlackMarble_2016_B1_gray.jpg
BlackMarble_2016_C1_gray.jpg
BlackMarble_2016_D1_gray.jpg
BlackMarble_2016_A2_gray.jpg
BlackMarble_2016_B2_gray.jpg
BlackMarble_2016_C2_gray.jpg
BlackMarble_2016_D2_gray.jpg
```

Keep source downloads outside the repository. They are large upstream inputs,
not runtime assets.

## Generate

Install Pillow if needed:

```sh
python3 -m pip install Pillow
```

Download missing sources into a temporary directory and generate z4...z6:

```sh
SOURCE_DIR="$(mktemp -d)"
python3 Tools/NightLights/generate_night_lights_tiles.py \
  --source-dir "$SOURCE_DIR" \
  --output-dir Server/NightLightsTiles/seed/night-lights/v1/tiles \
  --tile-size 1024 \
  --min-zoom 4 \
  --max-zoom 6 \
  --quality 90 \
  --download
```

If downloading separately, use the links from the NASA source page and then run
the same command without `--download`.

The generator verifies all source JPEGs against pinned byte sizes and SHA256
hashes before processing. Downloads are written to `.tmp` files and atomically
renamed only after validation.

The expected generated output for z4...z6 is:

```text
z4: 256 JPEGs
z5: 1024 JPEGs
z6: 4096 JPEGs
total: 5376 JPEGs plus night_lights_generation_metadata.json
```

The server manifest lives at
`Server/NightLightsTiles/seed/night-lights/v1/night_lights_manifest.json`.
Keep its `tileURLTemplate` aligned with the generated tile filenames.

## Runtime Storage

ImmersiveMap does not bundle night-light tiles. Generate or provide tile payloads
for the server and configure the app with `.nightLightsTileManifestURL(...)`.
Do not commit generated tile payloads.
