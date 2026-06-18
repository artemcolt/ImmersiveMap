# Night Lights Tile Generator

This tool generates the committed runtime tile set used by `NightLightsTileSet`.
It converts NASA Black Marble 2016 grayscale 500m source imagery into flat,
unique SwiftPM resource names:

```text
night_lights_<z>_<x>_<y>.jpg
night_lights_tiles_metadata.json
```

SwiftPM `.process("Render/EarthScene/Resources")` flattens processed resources.
Traditional `z/x/y.jpg` tile paths would produce duplicate `y.jpg` filenames, so
the runtime assets use the flat filename convention above.

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
  --output-dir ImmersiveMap/Render/EarthScene/Resources/NightLightsTiles \
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

The expected committed runtime output for z4...z6 is:

```text
z4: 256 JPEGs
z5: 1024 JPEGs
z6: 4096 JPEGs
total: 5376 JPEGs plus night_lights_tiles_metadata.json
```

## Why Assets Are Committed

ImmersiveMap is a standalone Swift Package. The night-lights tiles are committed
so package consumers get deterministic offline runtime resources without running
NASA downloads or image processing as part of their app build.

The committed z4...z6, 1024 px, JPEG quality 90 tile set is roughly 125 MB. This
is intentional: the repository carries the runtime cost so consuming apps avoid
network access, long image-processing steps, and non-reproducible build-time
downloads.
