import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "blender"))
from native_mesh_audit import (MAX_BYTES, MAX_VERTICES, blender_texture_coordinate,
                              blender_texture_pixels, read_samples, validate_samples)


def fixture():
    return {"samples": [{"name": "navy-rb-corrected", "time": 12, "minimumY": 0,
        "meshes": [{"name": "qa-triangle", "positions": [[0, 0, 0], [0, 1, 0], [1, 0, 0]],
                    "indices": [0, 1, 2], "tint": [0.1, 0.2, 0.3, 1],
                    "tintColourSpace": "Linear Rec.709"}]}]}


def textured_fixture():
    document = fixture()
    mesh = document["samples"][0]["meshes"][0]
    mesh["uvs"] = [[0, 0], [0, 1], [1, 0]]
    mesh["texture"] = {"width": 2, "height": 2, "pixelFormat": "rgba8Unorm_srgb",
        "colourSpace": "Display P3", "origin": "top-left",
        "rgba8": [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 31, 79, 151, 255]}
    return document


class NativeMeshAuditTests(unittest.TestCase):
    def test_valid_native_geometry_is_preserved(self):
        document = fixture()
        before = copy.deepcopy(document)
        self.assertIs(validate_samples(document), document["samples"])
        self.assertEqual(document, before)

    def test_unsafe_or_duplicate_sample_names_are_rejected(self):
        for name in ["../escape", "", "/tmp/test", "a" * 65]:
            document = fixture()
            document["samples"][0]["name"] = name
            with self.assertRaises(ValueError):
                validate_samples(document)
        document = fixture()
        document["samples"] *= 2
        with self.assertRaises(ValueError):
            validate_samples(document)

    def test_nonfinite_or_outsize_positions_are_rejected(self):
        for value in [float("nan"), float("inf"), -6, True]:
            document = fixture()
            document["samples"][0]["meshes"][0]["positions"][0][1] = value
            with self.assertRaises(ValueError):
                validate_samples(document)

    def test_indices_and_tints_are_bounded(self):
        for field, value in [("indices", [0, 1]), ("indices", [0, 1, 3]),
                             ("indices", [0, True, 2]), ("tint", [1, 0, 0, 1.1]),
                             ("tintColourSpace", "sRGB"), ("tintColourSpace", None)]:
            document = fixture()
            document["samples"][0]["meshes"][0][field] = value
            with self.assertRaises(ValueError):
                validate_samples(document)

    def test_measurement_and_geometry_must_agree(self):
        document = fixture()
        document["samples"][0]["minimumY"] = 0.1
        with self.assertRaisesRegex(ValueError, "minimum"):
            validate_samples(document)

    def test_mesh_budget_and_file_size_are_bounded(self):
        document = fixture()
        document["samples"][0]["meshes"][0]["positions"] = [[0, 0, 0]] * (MAX_VERTICES + 1)
        with self.assertRaisesRegex(ValueError, "budget"):
            validate_samples(document)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.json"
            path.write_text(json.dumps(fixture()))
            self.assertEqual(len(read_samples(path)), 1)
            path.write_bytes(b" " * (MAX_BYTES + 1))
            with self.assertRaisesRegex(ValueError, "2 MB"):
                read_samples(path)

    def test_native_texture_and_uvs_are_preserved(self):
        document = textured_fixture()
        before = copy.deepcopy(document)
        self.assertIs(validate_samples(document), document["samples"])
        self.assertEqual(document, before)

    def test_uv_count_finiteness_and_range_are_bounded(self):
        for uvs in [None, [[0, 0]], [[0, 0], [float("nan"), 0], [0, 1]],
                    [[0, 0], [2, 0], [0, 1]], [[0, 0], [True, 0], [0, 1]]]:
            document = textured_fixture()
            document["samples"][0]["meshes"][0]["uvs"] = uvs
            with self.assertRaisesRegex(ValueError, "UV"):
                validate_samples(document)

    def test_native_texture_format_dimensions_and_pixels_are_explicit(self):
        for field, value in [("width", True), ("height", 257), ("width", 256),
                             ("colourSpace", "sRGB"), ("origin", "bottom-left"),
                             ("pixelFormat", "astc_4x4_srgb"), ("pixelFormat", []),
                             ("pixelFormat", {}), ("rgba8", [1, 2, 3]),
                             ("rgba8", [True, 0, 0, 255] * 4),
                             ("rgba8", [255, 0, 0, 0] * 4)]:
            document = textured_fixture()
            document["samples"][0]["meshes"][0]["texture"][field] = value
            with self.assertRaises(ValueError):
                validate_samples(document)

    def test_blender_rows_flip_once_without_changing_channels(self):
        texture = textured_fixture()["samples"][0]["meshes"][0]["texture"]
        before = copy.deepcopy(texture)
        actual = blender_texture_pixels(texture)
        self.assertEqual(actual, [v / 255 for v in texture["rgba8"][8:] + texture["rgba8"][:8]])
        self.assertEqual(texture, before)

    def test_native_bottom_origin_uvs_do_not_receive_a_second_flip(self):
        texture = textured_fixture()["samples"][0]["meshes"][0]["texture"]
        pixels = blender_texture_pixels(texture)
        for uv, expected in [([0.25, 0.75], [255, 0, 0, 255]),
                             ([0.25, 0.25], [0, 0, 255, 255])]:
            u, v = blender_texture_coordinate(uv)
            self.assertEqual((u, v), tuple(uv))
            offset = (int(v * texture["height"]) * texture["width"] + int(u * texture["width"])) * 4
            self.assertEqual(pixels[offset:offset + 4], [value / 255 for value in expected])

    def test_uv_transfer_rejects_unbounded_coordinates(self):
        for uv in [None, [0], [0, 1, 2], [0, -0.1], [1.1, 0], [True, 0], [float("nan"), 0]]:
            with self.assertRaisesRegex(ValueError, "UV"):
                blender_texture_coordinate(uv)


if __name__ == "__main__":
    unittest.main()
