#!/usr/bin/env python3
# Copyright (c) 2025-2026 Artem Bobkin.
# SPDX-License-Identifier: MIT

import unittest
from pathlib import Path
import importlib.util
import json
import sys
import tempfile

from PIL import Image


SCRIPT_PATH = Path(__file__).with_name("generate_night_lights_tiles.py")
SPEC = importlib.util.spec_from_file_location("generate_night_lights_tiles", SCRIPT_PATH)
generator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = generator
SPEC.loader.exec_module(generator)


class CinematicNightLightsTests(unittest.TestCase):
    def test_cinematic_tile_uses_red_core_and_green_halo_channels(self):
        source = Image.new("L", (9, 9), 0)
        source.putpixel((4, 4), 255)

        result = generator.process_output_tile(source, style="cinematic")

        self.assertEqual(result.mode, "RGB")
        center = result.getpixel((4, 4))
        neighbor = result.getpixel((4, 5))
        corner = result.getpixel((0, 0))

        self.assertGreater(center[0], center[1])
        self.assertGreater(neighbor[1], 0)
        self.assertEqual(corner, (0, 0, 0))

    def test_raw_style_keeps_single_channel_output(self):
        source = Image.new("L", (2, 1))
        source.putpixel((0, 0), 32)
        source.putpixel((1, 0), 240)

        result = generator.process_output_tile(source, style="raw")

        self.assertEqual(result.mode, "L")
        self.assertEqual(result.getpixel((0, 0)), 32)
        self.assertEqual(result.getpixel((1, 0)), 240)

    def test_metadata_records_cinematic_style_and_channel_semantics(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_dir = Path(temporary_directory)
            config = generator.GenerationConfig(
                source_dir=output_dir,
                output_dir=output_dir,
                tile_size=1024,
                min_zoom=4,
                max_zoom=6,
                quality=90,
                download=False,
                style="cinematic",
            )

            generator.write_metadata(config)

            metadata = json.loads(
                (output_dir / generator.METADATA_FILE_NAME).read_text()
            )

        self.assertEqual(metadata["generationParameters"]["style"], "cinematic")
        self.assertEqual(
            metadata["generationParameters"]["channels"],
            {
                "red": "cinematic light core",
                "green": "cinematic light halo",
                "blue": "unused by runtime; decoded JPEG may contain compression leakage",
            },
        )

    def test_metadata_records_raw_style_and_channel_semantics(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_dir = Path(temporary_directory)
            config = generator.GenerationConfig(
                source_dir=output_dir,
                output_dir=output_dir,
                tile_size=256,
                min_zoom=0,
                max_zoom=0,
                quality=75,
                download=False,
                style="raw",
            )

            generator.write_metadata(config)

            metadata = json.loads(
                (output_dir / generator.METADATA_FILE_NAME).read_text()
            )

        self.assertEqual(metadata["generationParameters"]["style"], "raw")
        self.assertEqual(
            metadata["generationParameters"]["channels"],
            {
                "red": "raw grayscale night light intensity",
                "green": "same as red after RGB JPEG decode",
                "blue": "same as red after RGB JPEG decode",
            },
        )

    def test_cinematic_curve_compresses_highlights_and_preserves_dim_lights(self):
        values = [0, 4, 16, 64, 160, 255]
        mapped = [generator.cinematic_core_value(value) for value in values]

        self.assertEqual(mapped[0], 0)
        self.assertEqual(mapped[1], 0)
        self.assertGreater(mapped[2], 0)
        self.assertGreater(mapped[3], mapped[2])
        self.assertGreater(mapped[4], mapped[3])
        self.assertGreater(mapped[5], mapped[4])
        self.assertLess(mapped[5], 235)

    def test_crop_processed_tile_removes_processing_padding(self):
        source = Image.new("RGB", (8, 8))
        for y in range(source.height):
            for x in range(source.width):
                source.putpixel((x, y), (x, y, x + y))

        cropped = generator.crop_processed_tile(source, tile_size=4, padding=2)

        self.assertEqual(cropped.size, (4, 4))
        self.assertEqual(cropped.getpixel((0, 0)), source.getpixel((2, 2)))
        self.assertEqual(cropped.getpixel((3, 0)), source.getpixel((5, 2)))
        self.assertEqual(cropped.getpixel((0, 3)), source.getpixel((2, 5)))
        self.assertEqual(cropped.getpixel((3, 3)), source.getpixel((5, 5)))

    def test_padded_source_image_stitches_neighbor_margins(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_dir = Path(temporary_directory)
            bases = {
                "A1": 10,
                "B1": 30,
                "C1": 50,
                "D1": 70,
                "A2": 90,
                "B2": 110,
                "C2": 130,
                "D2": 150,
            }
            source_tiles = {}
            for row_index, row in enumerate(generator.SOURCE_ROWS):
                for column_index, column in enumerate(generator.SOURCE_COLUMNS):
                    key = f"{column}{row}"
                    path = source_dir / f"{key}.png"
                    image = Image.new("RGB", (3, 3))
                    for y in range(image.height):
                        for x in range(image.width):
                            image.putpixel((x, y), (bases[key], x, y))
                    image.save(path)
                    source_tiles[(column_index, row_index)] = generator.SourceTile(
                        key=key,
                        path=path,
                        column=column_index,
                        row=row_index,
                    )

            source_tile = source_tiles[(3, 0)]
            with Image.open(source_tile.path) as source:
                padded = generator.build_padded_source_image(
                    source=source,
                    source_tile=source_tile,
                    source_tiles_by_grid=source_tiles,
                    margin=1,
                )

        self.assertEqual(padded.size, (5, 5))
        self.assertEqual(padded.getpixel((1, 1)), (bases["D1"], 0, 0))
        self.assertEqual(padded.getpixel((0, 1)), (bases["C1"], 2, 0))
        self.assertEqual(padded.getpixel((4, 1)), (bases["A1"], 0, 0))
        self.assertEqual(padded.getpixel((1, 4)), (bases["D2"], 0, 0))
        self.assertEqual(padded.getpixel((4, 4)), (bases["A2"], 0, 0))
        self.assertEqual(padded.getpixel((1, 0)), (0, 0, 0))


if __name__ == "__main__":
    unittest.main()
