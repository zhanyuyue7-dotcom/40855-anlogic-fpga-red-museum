import importlib.util
import hashlib
import json
from pathlib import Path
import unittest

import numpy as np


SCRIPT = Path(__file__).resolve().parents[1] / "tools/extract_spectrum_animation.py"


class SpectrumExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("spectrum_extract", SCRIPT)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_dark_background_and_gaps_are_not_bars(self):
        pixels = np.full((12, 20, 3), (16, 16, 24), dtype=np.uint8)
        pixels[8:, :8] = (220, 60, 40)
        pixels[4:, 10:18] = (30, 200, 100)
        heights, colors = self.module.extract_frame(pixels, 2)
        self.assertEqual(heights.tolist(), [4, 8])
        self.assertEqual(colors.tolist(), [[220, 60, 40], [30, 200, 100]])

    def test_empty_frame_is_zero_and_has_no_color(self):
        heights, colors = self.module.extract_frame(np.zeros((12, 20, 3), np.uint8), 2)
        self.assertEqual(heights.tolist(), [0, 0])
        self.assertTrue(np.all(colors == 0))

    def test_loop_tail_ends_on_first_frame_without_changing_start(self):
        data = np.array([[0, 20], [20, 40], [80, 100], [100, 120]], dtype=np.uint8)
        loop = self.module.close_loop(data, 2)
        np.testing.assert_array_equal(loop[0], data[0])
        np.testing.assert_array_equal(loop[-1], data[0])
        self.assertTrue(np.all(loop[2] <= data[2]))
        np.testing.assert_array_equal(data[-1], [100, 120])

    def test_invalid_loop_blend_rejected(self):
        with self.assertRaises(ValueError):
            self.module.close_loop(np.zeros((4, 2), np.uint8), 5)

    def test_non_divisible_width_rejected(self):
        with self.assertRaises(ValueError):
            self.module.extract_frame(np.zeros((12, 21, 3), np.uint8), 2)

    def test_overlay_preserves_upper_half_and_bar_gap(self):
        heights = np.array([240, 20], np.uint8)
        palette = np.array([[220, 60, 40], [30, 200, 100]], np.uint8)
        image = np.array(self.module.overlay_frame(heights, palette, width=20))
        self.assertTrue(np.all(image[:240, :, 3] == 0))
        self.assertTrue(np.all(image[:, [9, 19], 3] == 0))
        np.testing.assert_array_equal(image[240, 0], [220, 60, 40, 255])
        self.assertEqual(image[459, 10, 3], 0)
        self.assertEqual(image[460, 10, 3], 255)

    def test_gif_timing_does_not_accumulate_rounding_error(self):
        durations = self.module.gif_durations(512, 15)
        self.assertLess(abs(sum(durations) - 512 * 1000 / 15), 10)
        self.assertEqual(set(durations), {60, 70})

    def test_generated_asset_contract_and_manifest_hash(self):
        root = SCRIPT.parents[1] / "assets/spectrum-animation"
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        values = bytes(int(line, 16) for line in (root / "heights.hex").read_text().splitlines())
        palette = (root / "palette.hex").read_text().splitlines()
        self.assertEqual(len(values), manifest["frames"] * manifest["bars"])
        self.assertEqual(len(values), 32768)
        self.assertEqual(len(palette), 64)
        self.assertTrue(all(len(rgb) == 6 and int(rgb, 16) >= 0 for rgb in palette))
        self.assertEqual(hashlib.sha256(values).hexdigest(), manifest["height_sha256"])
        self.assertEqual(max(values), 240)
        self.assertEqual(values[:64], values[-64:])
        self.assertEqual(manifest["kind"], "prerecorded_visual_animation_not_realtime_spectrum")

    def test_banked_mif_stream_matches_frame_major_heights(self):
        root = SCRIPT.parents[1]
        asset = root / "assets/spectrum-animation"
        values = bytes(int(line, 16) for line in (asset / "heights.hex").read_text().splitlines())
        for bank in range(8):
            mif = root / "work/lab_ex5_i2s/src/user_source/hdl_source" / f"spectrum_heights_bank{bank}.mif"
            actual = []
            for line in mif.read_text(encoding="ascii").splitlines():
                stripped = line.strip()
                if ":" in line and not stripped.startswith(("WIDTH", "DEPTH", "ADDRESS", "DATA", "CONTENT", "END")):
                    address, value = line.split(":", 1)
                    actual.append((int(address.strip()), int(value.rstrip(";").strip(), 16)))
            actual.sort()
            self.assertEqual([value for _, value in actual], list(values[bank * 4096:(bank + 1) * 4096]))


if __name__ == "__main__":
    unittest.main()
