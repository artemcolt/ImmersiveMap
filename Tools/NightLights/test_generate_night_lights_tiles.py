#!/usr/bin/env python3
# Copyright (c) 2025-2026 Artem Bobkin.
# SPDX-License-Identifier: MIT

import unittest
from pathlib import Path
import importlib.util
import sys

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
        source = Image.new("RGB", (8, 8), (0, 0, 0))
        cropped = generator.crop_processed_tile(source, tile_size=4, padding=2)

        self.assertEqual(cropped.size, (4, 4))


if __name__ == "__main__":
    unittest.main()
