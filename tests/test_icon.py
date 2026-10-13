"""Save icon build tests. Run: python3 -m unittest discover -s tests -p test_icon.py"""

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("build_icon", ROOT / "scripts" / "build_icon.py")
assert SPEC is not None and SPEC.loader is not None
icon = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(icon)


class IconTests(unittest.TestCase):
    def test_committed_icon_matches_artwork_build(self):
        with tempfile.TemporaryDirectory() as temp:
            built = icon.build(icon.SOURCE, Path(temp) / "SaveIcon.tga")
        self.assertEqual(built, icon.TARGET.read_bytes(),
                         "Rebuild with scripts/build_icon.py after changing the logo")

    def test_tga_header_and_top_left_origin(self):
        data = icon.TARGET.read_bytes()
        self.assertEqual(data[2], 2)
        self.assertEqual(int.from_bytes(data[12:14], "little"), 64)
        self.assertEqual(int.from_bytes(data[14:16], "little"), 64)
        self.assertEqual(data[16], 32)
        self.assertEqual(data[17], 0x28)
        self.assertEqual(len(data), 18 + 64 * 64 * 4)

    def test_box_filter_and_bgra_order(self):
        size = icon.CROP_LEFT + icon.CROP_SIZE
        rows = [bytes((10, 20, 30, 255)) * size for _ in range(icon.CROP_TOP + icon.CROP_SIZE)]
        pixels = icon.build_icon_pixels(size, len(rows), rows)
        self.assertEqual(len(pixels), 64)
        self.assertEqual(pixels[0][:4], bytes((10, 20, 30, 255)))
        self.assertEqual(icon.encode_tga(pixels)[18:22], bytes((30, 20, 10, 255)))

    def test_rejects_small_source(self):
        with self.assertRaises(ValueError):
            icon.build_icon_pixels(100, 100, [b"\0" * 400] * 100)


if __name__ == "__main__":
    unittest.main()
