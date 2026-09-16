import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "blender"))
from native_mesh_audit import MAX_BYTES, MAX_VERTICES, read_samples, validate_samples


def fixture():
    return {"samples": [{"name": "navy-rb-corrected", "time": 12, "minimumY": 0,
        "meshes": [{"name": "qa-triangle", "positions": [[0, 0, 0], [0, 1, 0], [1, 0, 0]],
                    "indices": [0, 1, 2], "tint": [0.1, 0.2, 0.3, 1]}]}]}


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
                             ("indices", [0, True, 2]), ("tint", [1, 0, 0, 1.1])]:
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


if __name__ == "__main__":
    unittest.main()
