#!/usr/bin/env python3
# Copyright (c) 2025-2026 Artem Bobkin.
# SPDX-License-Identifier: MIT

"""Generate bundled ImmersiveMap night-lights runtime tiles.

The source data is NASA Black Marble 2016 grayscale 500m imagery, published as
eight 21600x21600 JPEGs named A1..D2. Runtime output is a flat file set because
SwiftPM flattens processed resources and nested z/x/y.jpg names collide.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

Image: Any = None

GENERATOR_VERSION = 2
NASA_SOURCE_PAGE = "https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/"
SOURCE_BASE_URL = (
    "https://assets.science.nasa.gov/content/dam/science/esd/eo/images/"
    "imagerecords/144000/144897"
)
EXPECTED_SOURCES = {
    "A1": {
        "fileName": "BlackMarble_2016_A1_gray.jpg",
        "size": 5_906_921,
        "sha256": "4e5a1135eb97ffa17067128f278d329ccf8d8819f469c9c4a40ffda7b77c809b",
    },
    "B1": {
        "fileName": "BlackMarble_2016_B1_gray.jpg",
        "size": 8_388_924,
        "sha256": "19a3e114e0a3970577813ff54e81e60fe5f32b6c38148468625a8a02f594a33c",
    },
    "C1": {
        "fileName": "BlackMarble_2016_C1_gray.jpg",
        "size": 19_084_287,
        "sha256": "95c448f32e5c42bd4017d1c0394a56a93b77abb449cc1666573495df00f89a58",
    },
    "D1": {
        "fileName": "BlackMarble_2016_D1_gray.jpg",
        "size": 7_798_581,
        "sha256": "46f7261c8f70f6efea9505b86605ff3e0dee514a00f95f96339da04c2bb58662",
    },
    "A2": {
        "fileName": "BlackMarble_2016_A2_gray.jpg",
        "size": 1_858_943,
        "sha256": "13e06e1c9244e3d81c08b7d37cc447edaf77ceaecd5a007c2a208469ff788fbc",
    },
    "B2": {
        "fileName": "BlackMarble_2016_B2_gray.jpg",
        "size": 5_314_757,
        "sha256": "036ba07752c03f2a52f6038af863dd8d6c2e19f7b31ddae064f833d2ca823c8f",
    },
    "C2": {
        "fileName": "BlackMarble_2016_C2_gray.jpg",
        "size": 2_723_625,
        "sha256": "949c72ba9bd7b32e05f5009b9769e2aecf906742146498c1c4d3a27b05aa5c2c",
    },
    "D2": {
        "fileName": "BlackMarble_2016_D2_gray.jpg",
        "size": 2_900_043,
        "sha256": "fa13ddb4d30e4e0c9a4d1b2842fb67a96cc4abfe6837c4dfff2369b0fa2364c7",
    },
}
for source in EXPECTED_SOURCES.values():
    source["url"] = f"{SOURCE_BASE_URL}/{source['fileName']}"

SOURCE_COLUMNS = ("A", "B", "C", "D")
SOURCE_ROWS = ("1", "2")
METADATA_FILE_NAME = "night_lights_tiles_metadata.json"
OUTPUT_NAME_TEMPLATE = "night_lights_{z}_{x}_{y}.jpg"
MESH_BAND_HEIGHT = 8
WEB_MERCATOR_MAX_LATITUDE = 85.0511287798066
DOWNLOAD_TIMEOUT_SECONDS = 120


@dataclass(frozen=True)
class SourceTile:
    key: str
    path: Path
    column: int
    row: int


@dataclass(frozen=True)
class GenerationConfig:
    source_dir: Path
    output_dir: Path
    tile_size: int
    min_zoom: int
    max_zoom: int
    quality: int
    download: bool


def parse_args() -> GenerationConfig:
    parser = argparse.ArgumentParser(
        description="Generate flat ImmersiveMap night-lights JPEG resources."
    )
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--tile-size", default=1024, type=positive_int)
    parser.add_argument("--min-zoom", default=4, type=non_negative_int)
    parser.add_argument("--max-zoom", default=6, type=non_negative_int)
    parser.add_argument("--quality", default=90, type=jpeg_quality)
    parser.add_argument(
        "--download",
        action="store_true",
        help="Download missing NASA 2016 grayscale 500m JPEG sources into --source-dir.",
    )
    args = parser.parse_args()

    if args.min_zoom > args.max_zoom:
        parser.error("--min-zoom must be less than or equal to --max-zoom")

    return GenerationConfig(
        source_dir=args.source_dir,
        output_dir=args.output_dir,
        tile_size=args.tile_size,
        min_zoom=args.min_zoom,
        max_zoom=args.max_zoom,
        quality=args.quality,
        download=args.download,
    )


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def non_negative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be zero or greater")
    return parsed


def jpeg_quality(value: str) -> int:
    parsed = int(value)
    if not 1 <= parsed <= 100:
        raise argparse.ArgumentTypeError("must be between 1 and 100")
    return parsed


def main() -> int:
    config = parse_args()
    generate(config)
    return 0


def generate(config: GenerationConfig) -> None:
    load_pillow()

    config.source_dir.mkdir(parents=True, exist_ok=True)
    config.output_dir.mkdir(parents=True, exist_ok=True)

    if config.download:
        download_missing_or_invalid_sources(config.source_dir)

    source_tiles = discover_source_tiles(config.source_dir)
    validate_source_tiles(source_tiles)
    clear_previous_outputs(config.output_dir)

    expected_count = expected_tile_count(config.min_zoom, config.max_zoom)
    print(
        "Generating "
        f"{expected_count} JPEG tiles at z{config.min_zoom}...z{config.max_zoom} "
        f"into {config.output_dir}"
    )

    for source_tile in source_tiles:
        generate_from_source_tile(source_tile, config)

    write_metadata(config)


def download_missing_or_invalid_sources(source_dir: Path) -> None:
    for key in expected_source_keys():
        source = EXPECTED_SOURCES[key]
        destination = source_dir / source["fileName"]
        if destination.exists():
            try:
                validate_source_file(key, destination)
                print(f"Using existing verified source {destination.name}")
                continue
            except ValueError as error:
                print(f"Replacing invalid source {destination.name}: {error}")

        download_source_file(key, destination)


def download_source_file(key: str, destination: Path) -> None:
    source = EXPECTED_SOURCES[key]
    temporary_destination = destination.with_name(f"{destination.name}.tmp")
    temporary_destination.unlink(missing_ok=True)

    print(f"Downloading {key} from {source['url']}")
    try:
        with urllib.request.urlopen(source["url"], timeout=DOWNLOAD_TIMEOUT_SECONDS) as response:
            with temporary_destination.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)

        validate_source_file(key, temporary_destination)
        temporary_destination.replace(destination)
    except Exception:
        temporary_destination.unlink(missing_ok=True)
        raise


def discover_source_tiles(source_dir: Path) -> list[SourceTile]:
    discovered: list[SourceTile] = []
    for row_index, row in enumerate(SOURCE_ROWS):
        for column_index, column in enumerate(SOURCE_COLUMNS):
            key = f"{column}{row}"
            discovered.append(
                SourceTile(
                    key=key,
                    path=find_source_file(source_dir, key),
                    column=column_index,
                    row=row_index,
                )
            )
    return discovered


def find_source_file(source_dir: Path, key: str) -> Path:
    exact_names = (
        EXPECTED_SOURCES[key]["fileName"],
        f"BlackMarble_2016_{key}_geo_gray.jpg",
        f"{key}_gray.jpg",
        f"{key}.jpg",
    )
    for name in exact_names:
        candidate = source_dir / name
        if candidate.is_file():
            return candidate

    matches = sorted(
        candidate
        for candidate in source_dir.iterdir()
        if candidate.is_file()
        and candidate.suffix.lower() in (".jpg", ".jpeg")
        and key.lower() in candidate.stem.lower()
        and "gray" in candidate.stem.lower()
    )
    if matches:
        return matches[0]

    expected = ", ".join(exact_names)
    raise FileNotFoundError(
        f"missing source tile {key} in {source_dir}. Expected one of: {expected}"
    )


def validate_source_tiles(source_tiles: Iterable[SourceTile]) -> None:
    expected_size: tuple[int, int] | None = None
    for source_tile in source_tiles:
        validate_source_file(source_tile.key, source_tile.path)
        with Image.open(source_tile.path) as image:
            if expected_size is None:
                expected_size = image.size
            elif image.size != expected_size:
                raise ValueError(
                    f"{source_tile.path.name} has size {image.size}; "
                    f"expected {expected_size}"
                )
            if image.width != image.height:
                raise ValueError(
                    f"{source_tile.path.name} must be square; got {image.size}"
                )


def validate_source_file(key: str, path: Path) -> None:
    expected = EXPECTED_SOURCES[key]
    actual_size = path.stat().st_size
    if actual_size != expected["size"]:
        raise ValueError(
            f"{path.name} byte size {actual_size} does not match expected {expected['size']}"
        )

    actual_hash = sha256_file(path)
    if actual_hash != expected["sha256"]:
        raise ValueError(
            f"{path.name} SHA256 {actual_hash} does not match expected {expected['sha256']}"
        )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as input_file:
        while True:
            chunk = input_file.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def clear_previous_outputs(output_dir: Path) -> None:
    for path in output_dir.glob("night_lights_*_*_*.jpg"):
        path.unlink()
    metadata_path = output_dir / METADATA_FILE_NAME
    if metadata_path.exists():
        metadata_path.unlink()


def generate_from_source_tile(source_tile: SourceTile, config: GenerationConfig) -> None:
    with Image.open(source_tile.path) as opened:
        source = opened.convert("L")

    source_tile_size = source.width
    global_width = source_tile_size * len(SOURCE_COLUMNS)
    global_height = source_tile_size * len(SOURCE_ROWS)

    print(f"Processing {source_tile.key}: {source_tile.path.name}")
    for z in range(config.min_zoom, config.max_zoom + 1):
        tiles_per_axis = 1 << z
        x_start = source_tile.column * tiles_per_axis // len(SOURCE_COLUMNS)
        x_end = (source_tile.column + 1) * tiles_per_axis // len(SOURCE_COLUMNS)
        y_start = source_tile.row * tiles_per_axis // len(SOURCE_ROWS)
        y_end = (source_tile.row + 1) * tiles_per_axis // len(SOURCE_ROWS)

        for y in range(y_start, y_end):
            for x in range(x_start, x_end):
                image = render_tile(
                    source=source,
                    source_tile=source_tile,
                    z=z,
                    x=x,
                    y=y,
                    output_tile_size=config.tile_size,
                    global_width=global_width,
                    global_height=global_height,
                )
                output_path = config.output_dir / OUTPUT_NAME_TEMPLATE.format(z=z, x=x, y=y)
                image.save(
                    output_path,
                    format="JPEG",
                    quality=config.quality,
                    optimize=False,
                    progressive=False,
                )


def render_tile(
    source: Image.Image,
    source_tile: SourceTile,
    z: int,
    x: int,
    y: int,
    output_tile_size: int,
    global_width: int,
    global_height: int,
) -> Image.Image:
    source_x0 = x / (1 << z) * global_width - source_tile.column * source.width
    source_x1 = (x + 1) / (1 << z) * global_width - source_tile.column * source.width
    mesh = build_mercator_mesh(
        z=z,
        y=y,
        output_tile_size=output_tile_size,
        source_x0=source_x0,
        source_x1=source_x1,
        source_row_offset=source_tile.row * source.height,
        global_height=global_height,
    )
    return source.transform(
        (output_tile_size, output_tile_size),
        Image.Transform.MESH,
        mesh,
        resample=Image.Resampling.BICUBIC,
    )


def build_mercator_mesh(
    z: int,
    y: int,
    output_tile_size: int,
    source_x0: float,
    source_x1: float,
    source_row_offset: int,
    global_height: int,
) -> list[tuple[tuple[int, int, int, int], tuple[float, float, float, float, float, float, float, float]]]:
    mesh = []
    for top in range(0, output_tile_size, MESH_BAND_HEIGHT):
        bottom = min(top + MESH_BAND_HEIGHT, output_tile_size)
        source_y0 = mercator_pixel_y_to_equirectangular_y(
            z=z,
            tile_y=y,
            pixel_y=top,
            output_tile_size=output_tile_size,
            global_height=global_height,
        ) - source_row_offset
        source_y1 = mercator_pixel_y_to_equirectangular_y(
            z=z,
            tile_y=y,
            pixel_y=bottom,
            output_tile_size=output_tile_size,
            global_height=global_height,
        ) - source_row_offset
        mesh.append(
            (
                (0, top, output_tile_size, bottom),
                (
                    source_x0,
                    source_y0,
                    source_x0,
                    source_y1,
                    source_x1,
                    source_y1,
                    source_x1,
                    source_y0,
                ),
            )
        )
    return mesh


def mercator_pixel_y_to_equirectangular_y(
    z: int,
    tile_y: int,
    pixel_y: int,
    output_tile_size: int,
    global_height: int,
) -> float:
    tiles_per_axis = 1 << z
    normalized_y = (tile_y + pixel_y / output_tile_size) / tiles_per_axis
    latitude = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * normalized_y))))
    clamped_latitude = max(
        -WEB_MERCATOR_MAX_LATITUDE,
        min(WEB_MERCATOR_MAX_LATITUDE, latitude),
    )
    return (90.0 - clamped_latitude) / 180.0 * global_height


def write_metadata(config: GenerationConfig) -> None:
    metadata = {
        "version": 1,
        "format": "jpg",
        "tileSize": config.tile_size,
        "minZoom": config.min_zoom,
        "maxZoom": config.max_zoom,
        "source": "NASA Black Marble 2016",
        "attribution": "NASA Earth Observatory",
        "generatorVersion": GENERATOR_VERSION,
        "filenameTemplate": OUTPUT_NAME_TEMPLATE,
        "tileCount": expected_tile_count(config.min_zoom, config.max_zoom),
        "quality": config.quality,
        "generationParameters": {
            "tileSize": config.tile_size,
            "minZoom": config.min_zoom,
            "maxZoom": config.max_zoom,
            "quality": config.quality,
            "sourcePage": NASA_SOURCE_PAGE,
            "sourceGrid": {
                "columns": list(SOURCE_COLUMNS),
                "rows": list(SOURCE_ROWS),
            },
            "projection": "Web Mercator runtime tiles sampled from equirectangular NASA sources",
        },
        "sourceFiles": expected_source_metadata(),
    }
    metadata_path = config.output_dir / METADATA_FILE_NAME
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=False) + "\n")


def expected_tile_count(min_zoom: int, max_zoom: int) -> int:
    return sum((1 << z) * (1 << z) for z in range(min_zoom, max_zoom + 1))


def expected_source_keys() -> tuple[str, ...]:
    return tuple(f"{column}{row}" for row in SOURCE_ROWS for column in SOURCE_COLUMNS)


def expected_source_metadata() -> dict[str, dict[str, Any]]:
    return {
        key: {
            "fileName": EXPECTED_SOURCES[key]["fileName"],
            "url": EXPECTED_SOURCES[key]["url"],
            "size": EXPECTED_SOURCES[key]["size"],
            "sha256": EXPECTED_SOURCES[key]["sha256"],
        }
        for key in expected_source_keys()
    }


def load_pillow() -> None:
    global Image
    if Image is not None:
        return

    try:
        from PIL import Image as pillow_image
    except ImportError:
        print(
            "error: Pillow is required. Install it with:\n"
            "  python3 -m pip install Pillow",
            file=sys.stderr,
        )
        raise SystemExit(2)

    pillow_image.MAX_IMAGE_PIXELS = None
    Image = pillow_image


if __name__ == "__main__":
    raise SystemExit(main())
